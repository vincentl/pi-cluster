import re

def value(nest: dict, key: str):
    '''
    value(config,'a.b.c') looks up config[a][b][c]
    '''
    return [nest := nest[i] for i in key.split('.')][-1]

def template(line: str, config: dict):
    '''
    replace '{{a.b}}' with value config[a][b]
    '''
    return re.sub('{{([^}]+)}}', lambda m: value(config, m.group(1)), line)

def expand(kind, name, config):
    '''
    load message from templates/msgs and expand template parameters
    '''
    with open(f'templates/{kind}/{name}', 'r') as io:
        return ''.join([template(line, config) for line in io.readlines()])
