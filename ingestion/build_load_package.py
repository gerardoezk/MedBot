from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(
            "Uso: build_load_package.py BUILD_DIR REQUIREMENTS HANDLER"
        )

    build_dir = Path(sys.argv[1]).resolve()
    requirements = Path(sys.argv[2]).resolve()
    handler = Path(sys.argv[3]).resolve()

    if not requirements.exists():
        raise FileNotFoundError(f"No existe: {requirements}")

    if not handler.exists():
        raise FileNotFoundError(f"No existe: {handler}")

    if build_dir.exists():
        shutil.rmtree(build_dir)

    build_dir.mkdir(parents=True, exist_ok=True)

    pip_env = os.environ.copy()

    # Evita configuraciones globales que fuerzan --user.
    pip_env["PIP_CONFIG_FILE"] = os.devnull
    pip_env["PIP_USER"] = "false"

    # Evita otras configuraciones que podrían entrar en conflicto con --target.
    pip_env.pop("PIP_TARGET", None)
    pip_env.pop("PIP_PREFIX", None)
    pip_env.pop("PIP_ROOT", None)

    comando = [
        sys.executable,
        "-m",
        "pip",
        "install",
        "--quiet",
        "--platform",
        "manylinux2014_x86_64",
        "--implementation",
        "cp",
        "--python-version",
        "3.12",
        "--abi",
        "cp312",
        "--only-binary=:all:",
        "--target",
        str(build_dir),
        "-r",
        str(requirements),
    ]

    subprocess.run(
        comando,
        check=True,
        env=pip_env,
    )

    shutil.copy2(handler, build_dir / "handler.py")

    print(f"Paquete Lambda preparado en: {build_dir}")


if __name__ == "__main__":
    main()
