#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install MindStudio Ascend skills into a TRAE project.

Usage:
  ./install-trae-skills.sh [PROJECT_ROOT] [--no-backup] [--list-only]

Arguments:
  PROJECT_ROOT   Target TRAE project root. Defaults to current directory.

Options:
  --no-backup    Overwrite existing same-name skills without creating backups.
  --list-only    Only list skills discovered in this repository.
  -h, --help     Show this help.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_root="$script_dir"
project_root="$(pwd)"
no_backup=0
list_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-backup)
      no_backup=1
      shift
      ;;
    --list-only)
      list_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      project_root="$1"
      shift
      ;;
  esac
done

if [[ ! -d "$project_root" ]]; then
  echo "Project root does not exist: $project_root" >&2
  exit 1
fi

project_root="$(cd "$project_root" && pwd)"
target_skills_root="$project_root/.trae/skills"

skills=()
for skill_dir in "$source_root"/*; do
  if [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]]; then
    skills+=("$(basename "$skill_dir")")
  fi
done

if [[ ${#skills[@]} -eq 0 ]]; then
  echo "No skill directories with SKILL.md were found under $source_root" >&2
  exit 1
fi

if [[ "$list_only" -eq 1 ]]; then
  echo "Skills discovered in source:"
  for skill in "${skills[@]}"; do
    echo " - $skill"
  done
  exit 0
fi

mkdir -p "$target_skills_root"
timestamp="$(date +%Y%m%d-%H%M%S)"
backups=()

for skill in "${skills[@]}"; do
  src="$source_root/$skill"
  dst="$target_skills_root/$skill"

  if [[ -e "$dst" ]]; then
    if [[ "$no_backup" -eq 1 ]]; then
      rm -rf "$dst"
    else
      backup="$target_skills_root/${skill}.backup-${timestamp}"
      mv "$dst" "$backup"
      backups+=("$backup")
    fi
  fi

  cp -R "$src" "$dst"
done

if [[ -f "$source_root/README.md" ]]; then
  cp "$source_root/README.md" "$target_skills_root/README.md"
fi

if [[ -f "$source_root/Ascend Performance Orchestrator.md" ]]; then
  cp "$source_root/Ascend Performance Orchestrator.md" "$target_skills_root/Ascend Performance Orchestrator.md"
  if [[ -d "$target_skills_root/ascend-performance-orchestrator" ]]; then
    cp "$source_root/Ascend Performance Orchestrator.md" "$target_skills_root/ascend-performance-orchestrator/Ascend Performance Orchestrator.md"
  fi
fi

manifest="$target_skills_root/mindstudio-skills-install.json"
{
  echo "{"
  echo "  \"installed_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"source_root\": \"${source_root//\\/\\\\}\","
  echo "  \"project_root\": \"${project_root//\\/\\\\}\","
  echo "  \"target_skills_root\": \"${target_skills_root//\\/\\\\}\","
  echo "  \"skills\": ["
  for i in "${!skills[@]}"; do
    comma=","
    [[ "$i" -eq $((${#skills[@]} - 1)) ]] && comma=""
    echo "    \"${skills[$i]}\"$comma"
  done
  echo "  ],"
  echo "  \"backups\": ["
  for i in "${!backups[@]}"; do
    comma=","
    [[ "$i" -eq $((${#backups[@]} - 1)) ]] && comma=""
    echo "    \"${backups[$i]}\"$comma"
  done
  echo "  ]"
  echo "}"
} > "$manifest"

cat <<EOF

MindStudio Ascend skills installed for TRAE IDE.
Project root: $project_root
Target:       $target_skills_root
Installed:    ${#skills[@]} skills
Backups:      ${#backups[@]} existing skill directories
Manifest:     $manifest

Restart TRAE IDE or reload the project if the skills do not appear immediately.
EOF
