#!/usr/bin/env bash
set -e

# Default config path
config_file_path="config.yml"

# Check if config.yml exists in current directory
if [ -f "$config_file_path" ]; then
    echo "The $config_file_path file exists."
else
    echo ""
    echo "The $config_file_path file wasn't found in the directory."
    echo "Proceeding to look at the -p flag"

    config_file_path=""

    while getopts "p:" var; do
        case $var in
            p) config_file_path="$OPTARG" ;;
        esac
    done

    if [ -z "$config_file_path" ]; then
        echo ""
        echo "Error: Absolute path to config.yml wasn't provided using -p flag."
        echo "You can run: bash repo_creation.sh -p /absolute/path/to/config.yml"
        echo ""
        exit 1
    fi
fi

# Load values from config.yml
ORG_NAME=$(niet ".resources.org_name" "$config_file_path")
REPO_NAME=$(niet ".resources.repo_name" "$config_file_path")
DESCRIPTION="${REPO_NAME}_description"

GITHUB_PERSONAL_ACCESS_TOKEN=${GITHUB_PERSONAL_ACCESS_TOKEN:-$(niet ".resources.github_personal_access_token_classic" "$config_file_path")}
DATABRICKS_HOST=${DATABRICKS_HOST:-$(niet ".resources.databricks_host" "$config_file_path")}
DATABRICKS_PROFILE_NAME=$(niet -s ".resources.databricks_profile_name" "$config_file_path" || echo "DEFAULT")
DATABRICKS_TOKEN=${DATABRICKS_TOKEN:-$(niet -s ".resources.secrets.MLP_DEV_SECRET" "$config_file_path" || echo "")}
PROJECT_DIR=$(niet ".resources.target_directory_for_dab_project" "$config_file_path")
ADD_RULES=$(niet -s ".resources.add_main_branch_rules" "$config_file_path" || echo "true")

# Export for Databricks CLI
export DATABRICKS_HOST
export DATABRICKS_TOKEN
export DATABRICKS_PROFILE="$DATABRICKS_PROFILE_NAME"

echo "DATABRICKS_HOST=$DATABRICKS_HOST"
echo "DATABRICKS_TOKEN set? ${DATABRICKS_TOKEN:+yes}"

SECRETS_JSON=$(python3 - <<PY
import json, yaml
cfg = yaml.safe_load(open("$config_file_path")) or {}
print(json.dumps((cfg.get("resources") or {}).get("secrets") or {}))
PY
)

COLLABORATORS_JSON=$(python3 - <<PY
import json, yaml
cfg = yaml.safe_load(open("$config_file_path")) or {}
print(json.dumps((cfg.get("resources") or {}).get("collaborator_usernames") or {}))
PY
)

echo ""
echo "[GitHub Repository Creation For $REPO_NAME]"
echo ""

# Validate required values
for required_var in ORG_NAME REPO_NAME GITHUB_PERSONAL_ACCESS_TOKEN PROJECT_DIR DATABRICKS_HOST DATABRICKS_TOKEN; do
    if [ -z "${!required_var}" ]; then
        echo "Error: Missing required value: $required_var"
        exit 1
    fi
done

mkdir -p "$PROJECT_DIR"

echo '{"project_name":"'"$REPO_NAME"'"}' > "$PROJECT_DIR/databricks-inputs.json"

databricks bundle init https://github.com/ig-ds/MLP-DAB-Templates \
    --output-dir="$PROJECT_DIR" \
    --template-dir single-model-train \
    --config-file="$PROJECT_DIR/databricks-inputs.json"

rm -f "$PROJECT_DIR/databricks-inputs.json"

if [ ! -d "$PROJECT_DIR/$REPO_NAME" ]; then
    echo "Databricks Error: $PROJECT_DIR/$REPO_NAME does not exist."
    exit 1
fi

cd "$PROJECT_DIR/$REPO_NAME"

git init -b main
echo ".vscode/" >> .gitignore || true
git add .
git commit -m "initial commit: Setup with repo_creation.sh script"

echo "Creating GitHub repository..."

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
    "https://api.github.com/orgs/$ORG_NAME/repos" \
    -d '{
        "name":"'"$REPO_NAME"'",
        "description":"'"$DESCRIPTION"'",
        "private":true
    }')

if [ "$HTTP_STATUS" = "201" ]; then
    echo "Repository created successfully."

    git remote add origin "https://github.com/${ORG_NAME}/${REPO_NAME}.git"
    git push --set-upstream origin main

else
    echo "Error creating repository (HTTP $HTTP_STATUS)"
    exit 1
fi

echo ""
echo "Finished"
echo "Repository URL: https://github.com/$ORG_NAME/$REPO_NAME"
echo ""

