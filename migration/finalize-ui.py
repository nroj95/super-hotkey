"""One-time integration corrections; never executed by the suite or normal checks."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / 'modules/wonder-windows/fancyzones.ahk'
text = path.read_text(encoding='utf-8')
text = re.sub(r'\bsettings_path\b', 'fancyzones_settings_path', text)
path.write_text(text, encoding='utf-8', newline='\n')
