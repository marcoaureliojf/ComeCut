set -e

default_page="index.html"
server_url="http://127.0.0.1:8000/${default_page}"

# Collect python executables (unique)
declare -a choices
declare -a labels

while IFS= read -r p; do
  [[ -x "$p" ]] && p="$(readlink -f "$p")" || continue
  # avoid duplicates
  skip=0
  for ex in "${choices[@]}"; do [[ "$ex" == "python::$p" ]] && skip=1 && break; done
  [[ $skip -eq 1 ]] && continue
  choices+=("python::$p")
  labels+=("$p")
done < <(which -a python python3 2>/dev/null || true)

# If no python found, try conda envs
if [[ ${#choices[@]} -eq 0 && -x "$(command -v conda 2>/dev/null || true)" ]]; then
  # enable conda hook if available
  eval "$(conda shell.bash hook 2>/dev/null)" 2>/dev/null || true
  while IFS= read -r line; do
    # first token, strip leading '*' and whitespace
    token="${line%%[[:space:]]*}"
    token="${token#\*}"
    token="${token//[[:space:]]/}"
    [[ -z "$token" || "$token" == "base" ]] && continue
    choices+=("conda::$token")
    labels+=("(conda) $token")
  done < <(conda env list 2>/dev/null || true)
fi

if [[ ${#choices[@]} -eq 0 ]]; then
  echo "No available Python environment found"
  echo "Please install Python or Anaconda/Miniconda first"
  exit 1
fi

selected_index=0

# If only one choice, use it
if [[ ${#choices[@]} -eq 1 ]]; then
  selected_index=1
else
  echo "Multiple environments found, please select one:"
  for i in "${!labels[@]}"; do
    echo "[$((i+1))] ${labels[i]}"
  done
  echo
  while :; do
    read -rp "Please enter a number to select Python runtime environment (1-${#choices[@]}): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#choices[@]} )); then
      selected_index=$choice
      break
    fi
    echo "Invalid selection"
  done
fi

sel="${choices[$((selected_index-1))]}"
type="${sel%%::*}"
value="${sel#*::}"

# If conda chosen, attempt to activate
if [[ "$type" == "conda" ]]; then
  echo "Activating conda environment: $value"
  # try modern hook, fallback to sourcing conda.sh if possible
  if ! ( eval "$(conda shell.bash hook 2>/dev/null)" 2>/dev/null && conda activate "$value" ); then
    # try locate conda base
    base="$(conda info --base 2>/dev/null || true)"
    if [[ -n "$base" && -f "$base/etc/profile.d/conda.sh" ]]; then
      # shellcheck disable=SC1090
      source "$base/etc/profile.d/conda.sh"
      conda activate "$value"
    else
      echo "Could not initialize conda shell hook to activate environment."
      echo "You may need to run this script from a shell where 'conda activate' is available."
      exit 1
    fi
  fi

  echo
  echo "========================================"
  echo "Local HTTP server started!"
  echo "Access URL: $server_url"
  echo
  echo "Press Ctrl+C to stop the server"
  echo "========================================"
  echo

  # open browser
  xdg-open "$server_url" >/dev/null 2>&1 || true

  # run server using activated environment's python
  python -m http.server 8000 --bind 127.0.0.1
else
  # type == python, value is path to python executable
  selected_python="$value"
  echo "Using Python: $selected_python"
  echo
  echo "========================================"
  echo "Local HTTP server started!"
  echo "Access URL: $server_url"
  echo
  echo "Press Ctrl+C to stop the server"
  echo "========================================"
  echo

  xdg-open "$server_url" >/dev/null 2>&1 || true

  "$selected_python" -m http.server 8000 --bind 127.0.0.1
fi