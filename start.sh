#!/bin/bash
# Physis 실행 스크립트 — macOS / Linux

set -Eeuo pipefail

# 실패한 명령 전체나 API 키 대신 실패 위치만 출력합니다.
trap 'printf "\n오류: start.sh %s행에서 실행에 실패했습니다.\n" "$LINENO" >&2' ERR

die() {
    printf '오류: %s\n' "$*" >&2
    exit 1
}

# 어느 폴더에서 실행해도 프로젝트 폴더를 기준으로 동작합니다.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP="$SCRIPT_DIR/physis.py"
REQUIREMENTS="$SCRIPT_DIR/requirements.txt"
VENV_DIR="$SCRIPT_DIR/physis_env"
VENV_PYTHON="$VENV_DIR/bin/python"
INSTALL_STAMP="$VENV_DIR/.physis_dependencies_checksum"

[[ -f "$APP" ]] || die "physis.py가 없습니다."
[[ -f "$REQUIREMENTS" ]] || die "requirements.txt가 없습니다."

# 실행 가능 여부와 최소 Python 버전을 함께 검사합니다.
python_supported() {
    "$1" -c \
        'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' \
        >/dev/null 2>&1
}

printf 'Physis 실행을 준비합니다.\n'

if [[ -e "$VENV_DIR" || -L "$VENV_DIR" ]]; then
    # 잘못된 기존 폴더를 자동으로 삭제하거나 덮어쓰지 않습니다.
    [[ -f "$VENV_DIR/pyvenv.cfg" && -x "$VENV_PYTHON" ]] ||
        die "physis_env가 정상적인 가상환경이 아닙니다. 폴더를 백업하거나 이름을 바꾼 후 다시 실행하세요."

    python_supported "$VENV_PYTHON" ||
        die "가상환경의 Python을 실행할 수 없거나 버전이 3.11 미만입니다. physis_env를 다시 만들어 주세요."
else
    PYTHON_CMD=""

    # 기존 스크립트와 동일하게 Python 3.12를 우선 탐색합니다.
    for candidate in python3.12 python3.11 python3.13 python3.14 python3; do
        if command -v "$candidate" >/dev/null 2>&1 &&
            python_supported "$candidate"; then
            PYTHON_CMD="$candidate"
            break
        fi
    done

    [[ -n "$PYTHON_CMD" ]] ||
        die "Python 3.11 이상이 필요합니다. Python을 설치한 후 다시 실행하세요."

    printf '가상환경을 생성합니다.\n'
    "$PYTHON_CMD" -m venv "$VENV_DIR"
fi

# requirements.txt가 변경되었거나 설치 기록이 없으면 설치합니다.
DEPENDENCY_CHECKSUM="$(cksum < "$REQUIREMENTS")"
INSTALLED_CHECKSUM=""

if [[ -f "$INSTALL_STAMP" ]]; then
    INSTALLED_CHECKSUM="$(cat "$INSTALL_STAMP")"
fi

# 설치 단계 재실행: PHYSIS_REINSTALL=1 bash start.sh
if [[ "$INSTALLED_CHECKSUM" != "$DEPENDENCY_CHECKSUM" ||
      "${PHYSIS_REINSTALL:-0}" == "1" ]]; then
    printf '필요한 패키지를 설치합니다. 최초 설치는 시간이 걸릴 수 있습니다.\n'

    # 설치 실패 시 다음 실행에서 다시 시도하도록 기록을 제거합니다.
    rm -f -- "$INSTALL_STAMP"

    "$VENV_PYTHON" -m pip install -r "$REQUIREMENTS"
    "$VENV_PYTHON" -m pip check

    # 설치와 검증이 모두 성공한 경우에만 완료를 기록합니다.
    printf '%s\n' "$DEPENDENCY_CHECKSUM" > "$INSTALL_STAMP"
fi

printf '\nPhysis를 시작합니다.\n'
printf 'API 키는 .env, 환경변수 또는 프로그램 화면에서 설정하세요.\n'
printf '프로그램 종료: 이 터미널에서 Ctrl+C\n\n'

# -u: Python 출력을 지연 없이 표시합니다.
# "$@": --port 등의 실행 옵션을 Python 프로그램에 전달합니다.
exec "$VENV_PYTHON" -u "$APP" "$@"