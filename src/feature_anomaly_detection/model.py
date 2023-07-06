import torch
import torchvision.models as tvmodels
import yaml

CONV_MODULES = (torch.nn.modules.conv.Conv2d, torch.nn.modules.conv.Conv3d)


class Model:
    '''
    Holds a pretrained model for use with FADS
    '''

    def __init__(self, filepath, device):
        '''
        Gets a pretrained model
        '''
        # initial version suggested we'd have ability to alter and retrain
        # models as part of this.  on second thought, decided that should be
        # done prior to use due to complexity of training/altering and to
        # ensure FADS models are reproducible
        self.device = device
        self.activations = {}
        self.layer_names = {}
        self.layers = []
        self.get_model(filepath)

    def get_model(self, filepath):
        '''
        Gets pretrained model config/stats specified by filename and adds in
        activation hooks
        '''
        config = yaml.load(open(filepath), Loader=yaml.SafeLoader)
        if config['model_name'] and hasattr(tvmodels, config['model_name']):
            model = getattr(tvmodels, config['model_name'])
            self.model = model(pretrained=True)
        elif config['filepath']:
            # TODO: confirm this works
            self.model = torch.load(config['filepath'])
        else:
            raise ValueError('Config file does not designate model')
        self.model = self.model.to(self.device)
        self.model.eval()
        self.add_activation_hooks()

    def save_activation(self, name):
        self.layers.append(name)

        def hook(module, input, output):
            self.activations[name] = output
        return hook

    def get_next_name(self, name):
        if name in self.layer_names:
            self.layer_names[name] += 1
        else:
            self.layer_names[name] = 1
        return f"{name}{self.layer_names[name]}"

    def add_activation_hooks(self):
        '''
        Normally PyTorch wouldn't tell us all the intermediate numbers, so we have to tell PyTorch to save each of the activation energies
        as it calculates them.
        '''
        for module in self.model.modules():
            if isinstance(module, CONV_MODULES):
                name = self.get_next_name(type(module))
                module.register_forward_hook(self.save_activation(name))

    def get_activations(self, data):
        '''
        Return raw feature activations for a batch of data
        '''
        # reset activations before new run
        self.activations = {}

        # do forward pass data
        self.model(data)

        # doing this to have a consistent ordering for the activations
        activations = [self.activations[name] for name in self.layers]

        # reset activations for next run/free memory
        del self.activations
        self.activations = {}

        return activations
