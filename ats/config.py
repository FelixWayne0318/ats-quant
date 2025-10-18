from pathlib import Path
import yaml

PARAMS_PATH = Path("params.yml")

def load_params():
    if not PARAMS_PATH.exists():
        return {}
    return yaml.safe_load(PARAMS_PATH.read_text(encoding="utf-8"))
