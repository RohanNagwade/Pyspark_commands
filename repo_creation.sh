# INITIAL: Install libraries required for python code and for parsing the config.yml file
python3 -m venv myvenv
source myvenv/bin/activate
pip install pynacl
pip install niet
 
 
 
 
# Fetching the path for the config.yml file from the execution command using the -p flag
# If -p absolute_path_to_config_yml is not passed during execution of the command, then it is assumed that the config.yml file is present in the same folder as this script
config_file_path="config.yml"
 
if [ -f "$config_file_path" ]; then
    echo "The $config_file_path file exists."
else
    echo ""
    echo "The $config_file_path file wasn't found in the directory where create-dab-repo.sh script is located"
    echo "Proceeding to look at the -p flag"
    config_file_path="0"
    while getopts p: var
    do
      case $var in
      p) config_file_path=$OPTARG;;
      esac
    done
 
    if [ "$config_file_path" == "0" ]; then
        echo ""
        echo "Error: Absolute path to config.yml wasn't provided using -p flag."
        echo "You can run: bash create-dab-repo.sh -p /Users/absolute/path/to/your/config.yml"
        echo ""
        echo "OR"
        echo ""
        echo "Make sure that the create-dab-repo.sh script and the config.yml file is in the same folder"
        echo ""
        exit
    fi
fi
 
 
 
 
# Loading all the parameters from config.yml file
ORG_NAME=$(niet ".resources.org_name" "$config_file_path")
REPO_NAME=$(niet ".resources.repo_name" "$config_file_path")
DESCRIPTION=$(python3 -c "print('$REPO_NAME' + '_description')")
GITHUB_PERSONAL_ACCESS_TOKEN=$(niet ".resources.github_personal_access_token_classic" "$config_file_path")
DATABRICKS_HOST_URL=$(niet ".resources.databricks_host" "$config_file_path")
DATABRICKS_PROFILE_NAME=$(niet -s ".resources.databricks_profile_name" "$config_file_path" || echo "DEFAULT")
DATABRICKS_ACCESS_TOKEN_DEV=$(niet -s ".resources.secrets.MLP_DEV_SECRET" "$config_file_path" || echo "0")
PROJECT_DIR=$(niet ".resources.target_directory_for_dab_project" "$config_file_path")
ADD_RULES=$(niet -s ".resources.add_main_branch_rules" "$config_file_path" || echo True)
SECRETS=$(niet -s ".resources.secrets" "$config_file_path" || echo "0")
COLLABORATORS=$(niet -s ".resources.collaborator_usernames" "$config_file_path" || echo "0")
 
 
 
echo ""
echo "[Github Repository Creation For $REPO_NAME]"
echo ""
 
 
 
# Creating a databricks-inputs.json file to pass while performing databricks bundle init
write_to_json=$(python -c "
import json
 
data={
  'project_name': '$REPO_NAME',
}
 
json_object = json.dumps(data)
 
with open('$PROJECT_DIR/databricks-inputs.json', 'w') as outfile:
    outfile.write(json_object)
 
")
 
 
 
 
# Navigating to the project directory before performing databricks bundle init
cd "$PROJECT_DIR"
 
 
if [[ "$DATABRICKS_ACCESS_TOKEN_DEV" != "0" ]]; then
  echo "Running Databricks Configure..."
 
  # Exporting the required variables for databricks configure command
  export DATABRICKS_HOST="$DATABRICKS_HOST_URL"
  export DATABRICKS_TOKEN="$DATABRICKS_ACCESS_TOKEN_DEV"
  export DATABRICKS_PROFILE="$DATABRICKS_PROFILE_NAME"
 
  # Performing databricks configure
  databricks configure --token --profile "$DATABRICKS_PROFILE" --host "$DATABRICKS_HOST" --token "$DATABRICKS_TOKEN"
fi
 
 
 
# Performing databricks bundle init to create the DAB project directory inside the project directory specified in the config.yml file
databricks bundle init https://github.com/ig-ds/MLP-DAB-Templates --output-dir="$PROJECT_DIR" --template-dir single-model-train --config-file="$PROJECT_DIR/databricks-inputs.json"
 
 
 
# Deleting the databricks-inputs.json file from the project directory and navigating inside the newly created DAB project
rm "databricks-inputs.json"
 
 
 
# Check if the DAB project folder has been created or not, and display error message if not
if [ ! -d "$PROJECT_DIR/$REPO_NAME" ]; then
  echo ""
  echo "Databricks Error: $PROJECT_DIR/$REPO_NAME does not exist. ❌"
  echo "                  Please Verify that:"
  echo "                     (1) the databricks_host or databricks_profile_name have been set correctly."
  echo "                     (2) the databricks token possibly mentioned as MLP_DEV_SECRET has been set correctly."
  echo "                  Also ensure that the target directory path for DAB Project is valid."
  exit
fi
 
 
 
# If DAB project is created successfully then navigate to it
cd "$PROJECT_DIR/$REPO_NAME"
 
 
 
# Performing git operations to initialize the local directory for the DAB project
git init
echo ".vscode/" >> .gitignore
git add .
git commit -m 'initial commit: Setup with create-dab-repo.sh script'
 
 
 
# Use github API to log the user in and create the repo
echo "Logging User in and creating the Repo..."
res=$(curl -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -w "%{http_code}" \
  -o /dev/null \
  https://api.github.com/orgs/$ORG_NAME/repos \
  -d '{
    "name":"'$REPO_NAME'",
    "description":"'$DESCRIPTION'",
    "homepage":"https://github.com",
    "private":true,
    "visibility":"internal",
    "has_issues":true,
    "has_projects":true,
    "has_wiki":true
  }')
 
 
 
if [[ $res -eq 201 ]] ; then
  echo "Success: User Logged in and $REPO_NAME Repository Has Been Created! ✅"
 
 
  # Add the remote github repo to local repo and push
  git remote add origin https://github.com/${ORG_NAME}/${REPO_NAME}.git
  git push --set-upstream origin main
 
 
  # Add Rules to protect the main branch
  allow_rules=$(python3 -c "print(1 if $ADD_RULES == True else 0)")
  if [ $allow_rules -eq 1 ]; then
    echo "Setting up rules for $REPO_NAME Respository..."
    response=$(curl -L \
      -X PUT \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -w "%{http_code}" \
      -o /dev/null \
      https://api.github.com/repos/$ORG_NAME/$REPO_NAME/branches/main/protection \
      -d '{
        "required_status_checks":{
          "strict":false,
          "contexts":[]
        },
        "enforce_admins":null,
        "required_pull_request_reviews":{
          "dismissal_restrictions": {},
          "required_approving_review_count":2,
          "bypass_pull_request_allowances":{
            "users":[],
            "teams":[]
          }
        },
        "restrictions":null,
        "required_linear_history":false,
        "allow_force_pushes":false,
        "allow_deletions":false,
        "block_creations":false,
        "required_conversation_resolution":true,
        "lock_branch":false,
        "allow_fork_syncing":false
      }')
  
    if [ $response -eq 200 ]; then
      echo "Success: Rules Are Set for $REPO_NAME Repository ✅"
    else
      echo "Error: Couldn't Set Rules for $REPO_NAME Repository ❌"
    fi
  fi
 
 
 
  # Add Secrets to the Repository
 
  # Getting the public-key for encrypting the secrets
  if [[ "$SECRETS" != "0" ]]; then
    result=$(curl -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      https://api.github.com/repos/$ORG_NAME/$REPO_NAME/actions/secrets/public-key
    )
 
    PUBLIC_KEY_ID=$(python3 -c "print($result['key_id'])")
    PUBLIC_KEY=$(python3 -c "print($result['key'])")
 
    is_key=0
    for secret in $SECRETS;
    do
      if [ $is_key -eq 0 ]; then
        SECRET_NAME=$(python3 -c "print('$secret'[:-1])")
      else
        SECRET_VALUE=$secret
        
        # Encrypt the secret using public key
        ENCRYPTED_SECRET=$(python3 -c "
from base64 import b64encode
from nacl import encoding, public
 
public_key = '$PUBLIC_KEY'
secret_value = '$SECRET_VALUE'
 
public_key = public.PublicKey(public_key.encode('utf-8'), encoding.Base64Encoder())
sealed_box = public.SealedBox(public_key)
encrypted = sealed_box.encrypt(secret_value.encode('utf-8'))
print(b64encode(encrypted).decode('utf-8'))
        ")
 
        # Add the encrypted secret to the repo
        curl -L \
        -X PUT \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        https://api.github.com/repos/$ORG_NAME/$REPO_NAME/actions/secrets/$SECRET_NAME \
        -d '{
          "encrypted_value":"'$ENCRYPTED_SECRET'",
          "key_id":"'$PUBLIC_KEY_ID'"
        }'
 
        echo "Secret $SECRET_NAME added to Repository Secrets ✅"
      fi
      is_key=$(python3 -c "print(1 if $is_key == 0 else 0)")
    done
  else
    echo "No Secrets were specified in config.yml"
  fi
 
 
  # Adding Collaborators to the Repository
  if [[ "$COLLABORATORS" != "0" ]]; then
    is_key=0
    for collaborator in $COLLABORATORS;
    do
      if [ $is_key -eq 0 ];then
        collab_username=$(python3 -c "print('$collaborator'[:-1])")
      else
        collab_permission=$collaborator
        colab_response=$(curl -L \
        -X PUT \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -w "%{http_code}" \
        -o /dev/null \
        https://api.github.com/repos/$ORG_NAME/$REPO_NAME/collaborators/$collab_username \
        -d '{"permission":"'$collab_permission'"}')
 
        if [ $colab_response -eq 201 ]; then
          echo "Success: New invitation is created for $collab_username, with permission to $collab_permission ✅"
        elif [ $colab_response -eq 204 ]; then
          echo "Code 204 Occured While Adding $collab_username as Collaborator ✅:
          This can happen when
            - an existing collaborator is added as a collaborator
            - an organization member is added as an individual collaborator
            - an existing team member (whose team is also a repository collaborator) is added as an individual collaborator
          "
        elif [ $colab_response -eq 403 ]; then
          echo "Error While Adding $collab_username as Collaborator: Forbidden ❌"
        else
          echo "Error While Adding $collab_username as Collaborator: Validation failed, or the endpoint has been spammed ❌"
          echo "Check if:"
          echo "  - The Collaborator's Github Username is valid"
          echo "  - The permission granted to the Collaborator is valid"
        fi
      fi
      is_key=$(python3 -c "print(1 if $is_key == 0 else 0)")
    done
  else
    echo "No Collaborators were specified in config.yml"
  fi
 
 
 
  # Change to your project's root directory.
  cd "$PROJECT_DIR/$REPO_NAME"
 
  echo "Finished ✅"
  echo ""
  echo "Go to https://github.com/$ORG_NAME/$REPO_NAME to see."
  echo ""
  echo " * You're now in your project root. *"
  echo ""
  $SHELL
 
 
elif [[ $res -eq 422 ]] ; then
  echo "Error While Creating Repository: Validation failed, or the endpoint has been spammed ❌"
else
  echo "Error While Creating Repository: Request is Forbidden ❌"
fi