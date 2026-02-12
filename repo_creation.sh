# INITIAL: Install libraries required for python code and for parsing the config.yml file
# python3 -m venv myvenv
# source myvenv/bin/activate
# pip install pynacl
# pip install niet
 
 
 
 
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
GITHUB_PERSONAL_ACCESS_TOKEN=${GITHUB_PERSONAL_ACCESS_TOKEN:-$(niet ".resources.github_personal_access_token_classic" "$config_file_path")}
DATABRICKS_HOST_URL=$(niet ".resources.databricks_host" "$config_file_path")
DATABRICKS_PROFILE_NAME=$(niet -s ".resources.databricks_profile_name" "$config_file_path" || echo "DEFAULT")
DATABRICKS_ACCESS_TOKEN_DEV=${DATABRICKS_ACCESS_TOKEN_DEV:-$(niet -s ".resources.secrets.MLP_DEV_SECRET" "$config_file_path" || echo "")}
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
import shlex
import sys
import yaml

cfg = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8")) or {}
res = cfg.get("resources") or {}

data = {
    "ORG_NAME": res.get("org_name", ""),
    "REPO_NAME": res.get("repo_name", ""),
    "GITHUB_PERSONAL_ACCESS_TOKEN": res.get("github_personal_access_token_classic", ""),
    "DATABRICKS_HOST_URL": res.get("databricks_host", ""),
    "DATABRICKS_PROFILE_NAME": res.get("databricks_profile_name", "DEFAULT"),
    "DATABRICKS_ACCESS_TOKEN_DEV": (res.get("secrets") or {}).get("MLP_DEV_SECRET", ""),
    "PROJECT_DIR": res.get("target_directory_for_dab_project", ""),
    "ADD_RULES": bool(res.get("add_main_branch_rules", True)),
    "SECRETS_JSON": json.dumps(res.get("secrets") or {}),
    "COLLABORATORS_JSON": json.dumps(res.get("collaborator_usernames") or {}),
}

description = f"{data['REPO_NAME']}_description" if data["REPO_NAME"] else ""
data["DESCRIPTION"] = description

for k, v in data.items():
    if isinstance(v, bool):
        v = "true" if v else "false"
    print(f"{k}={shlex.quote(str(v))}")
PY
)"

for required_var in ORG_NAME REPO_NAME GITHUB_PERSONAL_ACCESS_TOKEN PROJECT_DIR; do
  if [[ -z "${!required_var}" ]]; then
    echo "Error: Missing required value in config.yml: $required_var"
    exit 1
  fi
done

mkdir -p "$PROJECT_DIR"

cat > "$PROJECT_DIR/databricks-inputs.json" <<EOF
{"project_name":"$REPO_NAME"}
EOF

echo ""
echo "[GitHub Repository Creation For $REPO_NAME]"
echo ""

if [[ -n "$DATABRICKS_ACCESS_TOKEN_DEV" && -n "$DATABRICKS_HOST_URL" ]]; then
  export DATABRICKS_HOST="$DATABRICKS_HOST_URL"
  export DATABRICKS_TOKEN="$DATABRICKS_ACCESS_TOKEN_DEV"
  export DATABRICKS_PROFILE="$DATABRICKS_PROFILE_NAME"
fi

databricks bundle init https://github.com/ig-ds/MLP-DAB-Templates \
  --output-dir="$PROJECT_DIR" \
  --template-dir single-model-train \
  --config-file="$PROJECT_DIR/databricks-inputs.json"

rm -f "$PROJECT_DIR/databricks-inputs.json"

if [[ ! -d "$PROJECT_DIR/$REPO_NAME" ]]; then
  echo ""
  echo "Databricks Error: $PROJECT_DIR/$REPO_NAME does not exist."
  echo "Please verify databricks host/profile/token values and target directory path."
  exit 1
fi

cd "$PROJECT_DIR/$REPO_NAME"

git init -b main
if ! grep -qxF ".vscode/" .gitignore 2>/dev/null; then
  echo ".vscode/" >> .gitignore
fi
git add .
git commit -m "initial commit: Setup with repo_creation.sh script"

echo "Logging user in and creating the repo..."
res=$(curl -sS -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -w "%{http_code}" \
  -o /dev/null \
  "https://api.github.com/orgs/$ORG_NAME/repos" \
  -d '{
    "name":"'"$REPO_NAME"'",
    "description":"'"$DESCRIPTION"'",
    "homepage":"https://github.com",
    "private":true,
    "has_issues":true,
    "has_projects":true,
    "has_wiki":true
  }')

if [[ "$res" == "201" ]]; then
  echo "Success: $REPO_NAME repository created."

  git remote add origin "https://github.com/${ORG_NAME}/${REPO_NAME}.git"
  git push --set-upstream origin main

  if [[ "${ADD_RULES,,}" == "true" ]]; then
    echo "Setting up protection rules for $REPO_NAME..."
    response=$(curl -sS -L \
      -X PUT \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -w "%{http_code}" \
      -o /dev/null \
      "https://api.github.com/repos/$ORG_NAME/$REPO_NAME/branches/main/protection" \
      -d '{
        "required_status_checks": {"strict": false, "contexts": []},
        "enforce_admins": null,
        "required_pull_request_reviews": {
          "dismissal_restrictions": {},
          "required_approving_review_count": 2,
          "bypass_pull_request_allowances": {"users": [], "teams": []}
        },
        "restrictions": null,
        "required_linear_history": false,
        "allow_force_pushes": false,
        "allow_deletions": false,
        "block_creations": false,
        "required_conversation_resolution": true,
        "lock_branch": false,
        "allow_fork_syncing": false
      }')

    if [[ "$response" == "200" ]]; then
      echo "Success: Branch protection rules set."
    else
      echo "Error: Could not set branch protection rules (HTTP $response)."
    fi
  fi

  if [[ "$SECRETS_JSON" != "{}" ]]; then
    result=$(curl -sS -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/$ORG_NAME/$REPO_NAME/actions/secrets/public-key")

    PUBLIC_KEY_ID=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("key_id",""))' <<< "$result")
    PUBLIC_KEY=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("key",""))' <<< "$result")

    if [[ -z "$PUBLIC_KEY_ID" || -z "$PUBLIC_KEY" ]]; then
      echo "Error: could not fetch repository public key for secrets."
      exit 1
    fi

    while IFS=$'\t' read -r SECRET_NAME SECRET_VALUE; do
      ENCRYPTED_SECRET=$(python3 - "$PUBLIC_KEY" "$SECRET_VALUE" <<'PY'
from base64 import b64encode
from nacl import encoding, public
import sys

public_key = sys.argv[1]
secret_value = sys.argv[2]

key = public.PublicKey(public_key.encode("utf-8"), encoding.Base64Encoder())
sealed_box = public.SealedBox(key)
encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
print(b64encode(encrypted).decode("utf-8"))
PY
)

      curl -sS -L \
        -X PUT \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$ORG_NAME/$REPO_NAME/actions/secrets/$SECRET_NAME" \
        -d '{"encrypted_value":"'"$ENCRYPTED_SECRET"'", "key_id":"'"$PUBLIC_KEY_ID"'"}' \
        >/dev/null

      echo "Secret $SECRET_NAME added."
    done < <(python3 - "$SECRETS_JSON" <<'PY'
import json
import sys

secrets = json.loads(sys.argv[1])
for k, v in secrets.items():
    if k == "MLP_DEV_SECRET":
        continue
    print(f"{k}\t{v}")
PY
)
  else
    echo "No repository secrets specified in config.yml"
  fi

  if [[ "$COLLABORATORS_JSON" != "{}" ]]; then
    while IFS=$'\t' read -r collab_username collab_permission; do
      colab_response=$(curl -sS -L \
        -X PUT \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -w "%{http_code}" \
        -o /dev/null \
        "https://api.github.com/repos/$ORG_NAME/$REPO_NAME/collaborators/$collab_username" \
        -d '{"permission":"'"$collab_permission"'"}')

      if [[ "$colab_response" == "201" ]]; then
        echo "Success: invitation created for $collab_username with $collab_permission."
      elif [[ "$colab_response" == "204" ]]; then
        echo "Info: $collab_username already has repository access (HTTP 204)."
      elif [[ "$colab_response" == "403" ]]; then
        echo "Error: forbidden while adding collaborator $collab_username."
      else
        echo "Error: failed to add collaborator $collab_username (HTTP $colab_response)."
      fi
    done < <(python3 - "$COLLABORATORS_JSON" <<'PY'
import json
import sys

collabs = json.loads(sys.argv[1])
for k, v in collabs.items():
    print(f"{k}\t{v}")
PY
)
  else
    echo "No collaborators specified in config.yml"
  fi

  echo ""
  echo "Finished"
  echo "Go to https://github.com/$ORG_NAME/$REPO_NAME to see."
  echo ""
elif [[ "$res" == "422" ]]; then
  echo "Error creating repository: validation failed, or endpoint has been spammed (HTTP 422)."
else
  echo "Error creating repository: request forbidden or failed (HTTP $res)."
fi
