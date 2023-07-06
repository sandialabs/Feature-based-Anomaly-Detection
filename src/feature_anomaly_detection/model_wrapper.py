import torch
import torchvision.transforms as T
import yaml

from feature_anomaly_detection.model import Model

models = {}


class ModelWrapper:
    '''
    Wraps a Model and stores the nominal stats
    '''
    def __init__(self, filename, device, dimensions=2, feature_agg_args={},
                 feature_aggregation=torch.amax, transforms=None,
                 rotation_inv=False, resize=None):
        '''
        Return a model wrapper for model specified in filename

        parameters:
            filename: model config file to use
            device: torch device to use for all gpu operations
            dimensions: input dimensionality
            feature_aggregation: aggregation function to collapse raw features
            feature_agg_args: arguments to use with aggregation
            transforms: torchvision transforms to be applied to all incoming
            data (e.g. convert color to grayscale)
            rotation_inv: Whether to process activations in such a way that
            rotation does not affect end output (2D only)
            resize: value to resize as done by torchvision.transforms.Resize

        returns:
            ModelWrapper with model set to model specified by filename
        '''
        config = yaml.load(open(filename), Loader=yaml.SafeLoader)
        if 'model_name' in config:
            model_name = config['model_name']
        elif 'filename' in config:
            model_name = config['filename']
        else:
            raise ValueError(f'Config {filename} does not designate model')

        # use existing model if already loaded
        if model_name in models:
            self.model = models[model_name]
        else:
            self.model = Model(filename, device)
            models[model_name] = self.model

        self.device = device
        self.aggregation = feature_aggregation
        self.agg_args = feature_agg_args.copy()
        self.agg_args['dim'] = tuple((torch.arange(dimensions) - dimensions))

        self.nominal_mean = None
        self.nominal_std = None
        self.max_dev = None
        self.transforms = transforms
        self.rotation_inv = rotation_inv
        if 'wrapper' in config:
            for key in config['wrapper']:
                self.__dict__[key] = config['wrapper'][key]
        if 'training_input' in config:
            self.training_stats = config['training_input']
        else:
            self.training_stats = None

        if resize:
            if self.transforms:
                self.transforms = T.Compose([
                    self.transforms,
                    T.Resize(resize)
                ])
            else:
                self.transforms = T.Resize(resize)

    def normalize(self, data):
        # TODO: handle 3D data, possibly store dataset mean/std to avoid batch
        # size issues, and if so the mean/std belong in wrapper/fads model
        dims = [0, *range(2, len(data.shape))]
        mean = data.mean(dim=dims, keepdim=True)
        std = data.std(dim=dims, keepdim=True)
        return (data - mean) / std

    def apply_transforms(self, data):
        '''
        Apply any wrapper defined transforms (if any)
        '''
        if self.transforms:
            return self.transforms(data)
        return data

    def get_training_stats(self, dataset):
        mean, mean_sq, count = 0, 0, 0
        for data, _ in dataset:
            dims = [0, *range(2, len(data.shape))]
            # Mean over batch, height and width, but not over the channels
            mean += torch.mean(data, dim=dims)
            mean_sq += torch.mean(data**2, dim=dims)
            count += 1

        mean = mean / count

        # std = sqrt(E[X^2] - (E[X])^2)
        std = (mean_sq / count - mean ** 2) ** 0.5
        self.training_stats = {'mean': mean, 'std': std}
        self.training_stats = {k: torch.reshape(v, (1, v.shape[0])) for k, v in self.training_stats.items()}

    def prep_nominal_stats(self, dataset):
        '''
        Go through nominal dataset and calculate activation stats for the
        entire dataset
        '''
        if not self.training_stats:
            print("prep_nominal_stats calculating dataset normalization values...")
            self.get_training_stats(dataset)
        self.normalize = T.Normalize(mean=self.training_stats['mean'],
                                     std=self.training_stats['std'])
        activations = []
        # get all activations for the "training" dataset
        for i, (data, _) in enumerate(dataset):
            print('prep_nominal_stats batch', i)
            # Send data to GPU, get activations and immediately detach to allow the GPU to free backprop memory.
            activation = self.get_activations(data.to(self.device)).detach()
            activations.append(activation)
            del data, activation
        activations = torch.cat(activations, dim=0)

        self.nominal_mean = activations.mean(dim=0)
        self.nominal_std = activations.std(dim=0, unbiased=False) + 1e-5

        r_vector = self.calc_r_vector(activations)
        # r is the difference between activation energy and the mean activation energy for each feature.
        # (Why not median?)
        # r is then normalized by the standard deviation of the activation energy (for each feature).
        # The maximum deviation, then, is a measure of how far this feature gets from the mean within the training dataset of "normal" data.
        # dim=0 is over all observations, so for each feature we are taking the maximum over all observations.
        self.max_dev = torch.abs(r_vector.amax(dim=0, keepdims=True)) + 1e-5

        return r_vector / self.max_dev

    def get_activations(self, data):
        '''
        Calculate the activations for a particular batch of data
        '''
        # TODO handle 3-d models that treat a dimension specially
        # specifically, permute/flip data so appropriate dimensionality is
        # passed to the model
        try:
            data = self.normalize(data)
            transformed_data = self.apply_transforms(data)
        except (RuntimeError):
            data = torch.movedim(data, 1, -1)
            data = self.normalize(data)
            transformed_data = self.apply_transforms(data)
            transformed_data = torch.movedim(transformed_data, -1, 1)
        del data
        raw_activations = self.model.get_activations(transformed_data)

        # TODO: handle 3-D, even if just throwing an exception
        if self.rotation_inv:
            # record activations for rotated inputs
            raw_activations_T = self.model.get_activations(
                torch.transpose(transformed_data, -2, -1)
            )
            # transpose back to make activations line back up between the
            # transposed inputs and the normal inputs
            raw_activations_T = [torch.transpose(raw_activations_T[i], -2, -1)
                                 for i in range(len(raw_activations_T))]
            # each activation varies in shape, have to process each element
            # individually
            raw_activations = [torch.sqrt(raw_activations[i] ** 2 +
                                          raw_activations_T[i] ** 2)
                               for i in range(len(raw_activations))]
            del raw_activations_T
        del transformed_data
        activations = self.aggregate_activations(raw_activations).cpu()
        del raw_activations
        return activations

    def aggregate_activations(self, activations):
        '''
        Aggregate the activations into a consistent size per feature
        '''
        out = []
        for feature in activations:
            out.append(self.aggregation(feature, **self.agg_args))
        return torch.cat(out, dim=1)

    def get_r_vector(self, data):
        '''
        Calculate the r vector for a particular batch of data
        '''
        activations = self.get_activations(data)
        return self.calc_r_vector(activations) / self.max_dev

    def calc_r_vector(self, activations):
        return torch.abs(activations - self.nominal_mean) / self.nominal_std
