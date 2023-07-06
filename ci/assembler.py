# https://github.com/tensorflow/tensorflow/tree/master/tensorflow/tools/dockerfiles
# https://github.com/tensorflow/tensorflow/blob/master/tensorflow/tools/dockerfiles/assembler.py
# https://github.com/tensorflow/community/blob/master/rfcs/20180731-dockerfile-assembler.md

# We eventually want to assemble Dockerfiles from partials like TensorFlow.
# But we aren't doing that yet.
# This is just a tiny starting point that assembles a script file to be run in each Dockerfile.

import os
import pathlib

import ruamel.yaml


def append_script_to_file(scriptYAML, filepath):
  with open(filepath, 'a') as omnibus:
    for index, line in enumerate(scriptYAML):
      print(line, file=omnibus)
      if index in mapLinesToCommentsAfterThatLine:
        entry = mapLinesToCommentsAfterThatLine[index]
        assert type(entry) is list
        assert len(entry) == 4
        # https://sourceforge.net/p/ruamel-yaml/code/ci/default/tree/tokens.py#l249
        commentToken = entry[0]
        assert type(commentToken) is ruamel.yaml.tokens.CommentToken
        comment = commentToken.value
        assert type(comment) is str
        omnibus.write(comment)


if __name__ == "__main__":
    if pathlib.Path('.before_script.yml').exists():
        yaml = ruamel.yaml.YAML()
        scriptYAML = yaml.load(pathlib.Path('.before_script.yml'))
        assert type(scriptYAML) is ruamel.yaml.comments.CommentedMap
        before_script = scriptYAML['.job-that-requires-environment']['before_script']
        assert type(before_script) is ruamel.yaml.comments.CommentedSeq
        assert type(before_script.ca) is ruamel.yaml.comments.Comment
        mapLinesToCommentsAfterThatLine = before_script.ca.items
        if os.path.exists(os.path.join('dockerfiles', 'before_script.sh')):
            os.remove(os.path.join('dockerfiles', 'before_script.sh'))
        append_script_to_file(before_script, os.path.join('dockerfiles', 'before_script.sh'))
    else:
        print('assembler.py does not find any .before_script.yml.')
