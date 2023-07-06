import torch

from feature_anomaly_detection.model_wrapper import ModelWrapper


class FeatureAnomalyDetectionSystem:
    '''
    Container for applying FADS to a set of models specific to a particular
    nominal dataset
    '''
    def __init__(self, dataset, model_files, models=(), device=None):
        '''
        parameters:
            dataset_path: location of the dataset files
            model_files: location(s) of the models to use
            models: a list of ModelWrappers to include (if you need finer
            grained instantiation control for a particular model)
            device: torch device models and data should be processed on
        '''
        self.dataset = dataset
        if device:
            self.device = device
            print('FADS received device =', device)
        else:
            self.device = torch.device('cpu')
            print('FADS device =', self.device)

        self.models = []
        for model in models:
            if isinstance(model, ModelWrapper):
                self.models.append(model)
            else:
                # maybe we should just do duck typing here?  I could see
                # passing in a Model being a common mistake that's likely to
                # cause issues though
                raise ValueError('models must be a ModelWrapper (or subclass')
        for filepath in model_files:
            self.models.append(ModelWrapper(filepath, self.device))

    def prep_nominal_stats(self):
        '''
        Initialize the stats for the nominal dataset
        '''
        activations = []
        for i, model in enumerate(self.models):
            print('model', i + 1)
            out = model.prep_nominal_stats(self.dataset)
            activations.append(out)
        return torch.cat(activations, dim=0)

    def evaluate(self, data):
        '''
        Evaluate data against models

        parameters:
            data: Batch or dataloader containing data to be evaluated.  If data
            is a dataloader, gradient information will be dropped.

        Returns r_vector (metrics?)
        '''
        r_vector = self.get_combined_r_vectors(data)
        # TODO decide how to pick various metrics and evaluate against them
        # r_vector.max() > 1.9 means if the deviation in *any* feature exceeds that threshold.
        return r_vector, r_vector.max() > 1.9

    def get_combined_r_vectors(self, data):
        '''
        Evaluate data against models

        parameters:
            data: Batch or dataloader containing data to be evaluated.  If data
            is a dataloader, gradient information will be dropped.

        Returns r_vector
        '''
        model_vectors = []
        for model in self.models:
            if isinstance(data, torch.utils.data.DataLoader):
                vectors = []
                for d, _ in data:
                    r_vectors = model.get_r_vector(d.to(self.device))
                    vectors.append(r_vectors.detach().cpu())
                model_vectors.append(torch.cat(vectors))
            else:
                model_vectors.append(model.get_r_vector(data.to(self.device)))
        r_vector = torch.stack(model_vectors)
        return r_vector

    def evaluate_and_localize(self, data):
        '''
        Takes data and calls evaluate on it.

        parameters:
            data: Batch of data to be evaluated.  Data cannot be a dataloader
            and must be individual batches.

        Returns localization information and evaluation score
        '''
        data = torch.FloatTensor(data, requires_grad=True)
        r_vector = self.evalutate(data)
        return r_vector
        # TODO: put in localization code
        # return localized, r_vector
