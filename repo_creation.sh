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
DATABRICKS_HOST_URL=${DATABRICKS_HOST:-$(niet ".resources.databricks_host" "$config_file_path")}
DATABRICKS_PROFILE_NAME=$(niet -s ".resources.databricks_profile_name" "$config_file_path" || echo "DEFAULT")
DATABRICKS_ACCESS_TOKEN_DEV=${DATABRICKS_TOKEN:-$(niet -s ".resources.secrets.MLP_DEV_SECRET" "$config_file_path" || echo "")}
PROJECT_DIR=$(niet ".resources.target_directory_for_dab_project" "$config_file_path")
ADD_RULES=$(niet -s ".resources.add_main_branch_rules" "$config_file_path" || echo "true")

echo ""
echo "[GitHub Repository Creation For $REPO_NAME]"
echo ""

# Validate required values
for required_var in ORG_NAME REPO_NAME GITHUB_PERSONAL_ACCESS_TOKEN PROJECT_DIR; do
    if [ -z "${!required_var}" ]; then
        echo "Error: Missing required value: $required_var"
        exit 1
    fi
done

mkdir -p "$PROJECT_DIR"

# Creating a databricks-inputs.json file using Python (like the original script)
python3 - <<PY
import json

data = {
    'project_name': '$REPO_NAME',
}

json_object = json.dumps(data)

with open('$PROJECT_DIR/databricks-inputs.json', 'w') as outfile:
    outfile.write(json_object)
PY

# Change to project directory before running bundle init
cd "$PROJECT_DIR"

# Configure Databricks if token is available
if [[ -n "$DATABRICKS_ACCESS_TOKEN_DEV" && -n "$DATABRICKS_HOST_URL" ]]; then
    echo "Running Databricks Configure..."
    
    # Export the required variables for databricks configure command
    export DATABRICKS_HOST="$DATABRICKS_HOST_URL"
    export DATABRICKS_TOKEN="$DATABRICKS_ACCESS_TOKEN_DEV"
    export DATABRICKS_PROFILE="$DATABRICKS_PROFILE_NAME"
    
    echo "DATABRICKS_HOST=$DATABRICKS_HOST"
    echo "DATABRICKS_TOKEN set? ${DATABRICKS_TOKEN:+yes}"
    
    # Performing databricks configure
    databricks configure --token --profile "$DATABRICKS_PROFILE_NAME" --host "$DATABRICKS_HOST_URL" --token "$DATABRICKS_ACCESS_TOKEN_DEV"
fi

# Run databricks bundle init
# Note: Newer CLI versions don't support --output-dir, so we cd to PROJECT_DIR first
databricks bundle init default-python \
    --config-file="databricks-inputs.json"

# Clean up the input file
rm -f "databricks-inputs.json"

# Check if the repo directory was created
if [ ! -d "$REPO_NAME" ]; then
    echo ""
    echo "Databricks Error: $PROJECT_DIR/$REPO_NAME does not exist. ❌"
    echo "                  Please Verify that:"
    echo "                     (1) the databricks_host or databricks_profile_name have been set correctly."
    echo "                     (2) the databricks token possibly mentioned as MLP_DEV_SECRET has been set correctly."
    echo "                  Also ensure that the target directory path for DAB Project is valid."
    exit 1
fi

# Move into the newly created repo directory
cd "$REPO_NAME"

# Initialize git repository
git init -b main
echo ".vscode/" >> .gitignore || true
git add .
git commit -m "initial commit: Setup with repo_creation.sh script"

echo "Creating GitHub repository..."

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/$ORG_NAME/repos" \
    -d '{
        "name":"'"$REPO_NAME"'",
        "description":"'"$DESCRIPTION"'",
        "private":true
    }')

if [ "$HTTP_STATUS" = "201" ]; then
    echo "Success: Repository $REPO_NAME Has Been Created! ✅"

    git remote add origin "https://github.com/${ORG_NAME}/${REPO_NAME}.git"
    git push --set-upstream origin main

    echo ""
    echo "Finished ✅"
    echo ""
    echo "Go to https://github.com/$ORG_NAME/$REPO_NAME to see."
    echo ""

else
    echo "Error creating repository (HTTP $HTTP_STATUS) ❌"
    exit 1
fi