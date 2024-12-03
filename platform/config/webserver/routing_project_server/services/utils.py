import os
import subprocess
from pathlib import Path

def get_qrcode(file_path: str, overwrite=True) -> os.PathLike:
    """Generates or updates the qr-code for a given file. Returns None or a path to the .png file."""
    file_path = Path(file_path)
    qr_code_path = file_path.with_suffix('.png')

    if not file_path.is_file():
        print("Error, file not found: " + file_path.as_posix())
        return None

    if qr_code_path.is_file() and not overwrite:
        return qr_code_path

    check_version = subprocess.run(["qrencode --version"], shell=True, timeout = 2, capture_output = True, text=True)
    if check_version.returncode != 0:
        print("Error, qrencode not installed. \r\nStderr:\t" + check_version.stderr)
        return None

    command = [str("qrencode -r " + file_path.as_posix() + " -o " + qr_code_path.as_posix())]
    generate_qr_code = subprocess.run(command, shell=True, timeout = 2)

    if generate_qr_code.returncode != 0:
        print("Error when generating the qrcode. \r\nStderr:\t" + generate_qr_code.stderr)
        return None

    else:
        return qr_code_path