#!/bin/bash

# Ensure you are logged in to OpenShift and have the necessary permissions
oc whoami &>/dev/null
if [ $? -ne 0 ]; then
  echo "Error: You must be logged into OpenShift."
  exit 1
fi

# Variables
IDP_NAME="password"
SECRET_NAME="htpasswd-secret"
NAMESPACE="openshift-config"
HTPASSWD_FILE="htpasswd"
AUTHENTICATION_NAMESPACE="openshift-authentication"
POD_LABEL="app=oauth-openshift"

# Function to extract htpasswd file from OpenShift secret
extract_htpasswd() {
  if oc get secret $SECRET_NAME -n $NAMESPACE &>/dev/null; then
    echo "Extracting htpasswd file from secret..."
    oc extract secret/$SECRET_NAME --to=. -n $NAMESPACE --confirm
  else
    echo "Secret not found in OpenShift. Creating an empty htpasswd file..."
    touch $HTPASSWD_FILE
  fi
}

# Function to add a user to the cluster-admin role
add_cluster_admin() {
  echo "Existing users:"
  awk -F: '{ print $1 }' $HTPASSWD_FILE
  read -p "Enter the username to add to cluster-admin: " username
  # Check if the user exists
  if ! grep -q "^$username:" $HTPASSWD_FILE; then
    echo "The user $username does not exist."
    return
  fi
  oc adm policy add-cluster-role-to-user cluster-admin $username
  echo "The user $username has been added to the cluster-admin role."
}

# Function to remove a user from the cluster-admin role
remove_cluster_admin() {
  read -p "Enter the username to remove from cluster-admin: " username
  oc adm policy remove-cluster-role-from-user cluster-admin $username
  echo "The user $username has been removed from the cluster-admin role."
}

# Function to handle adding a new user
add_user() {
  read -p "Enter the username: " username
  # Check if the user already exists
  if grep -q "^$username:" $HTPASSWD_FILE; then
    read -p "The user already exists. Do you want to update the password? (y/n): " update
    if [ "$update" != "y" ]; then
      echo "Operation cancelled."
      return
    fi
  fi
  read -s -p "Enter the password: " password
  echo
  htpasswd -B -b $HTPASSWD_FILE $username $password
}

# Function to handle removing a user
remove_user() {
  echo "Existing users:"
  awk -F: '{ print $1 }' $HTPASSWD_FILE
  read -p "Enter the username to remove: " username
  # Check if the user exists
  if ! grep -q "^$username:" $HTPASSWD_FILE; then
    echo "The user $username does not exist."
    return
  fi
  htpasswd -D $HTPASSWD_FILE $username
}

# Function to handle changing a user's password
change_password() {
  echo "Existing users:"
  awk -F: '{ print $1 }' $HTPASSWD_FILE
  read -p "Enter the username whose password you want to change: " username
  # Check if the user exists
  if ! grep -q "^$username:" $HTPASSWD_FILE; then
    echo "The user $username does not exist."
    return
  fi
  read -s -p "Enter the new password: " password
  echo
  htpasswd -b $HTPASSWD_FILE $username $password
}

# Check if the "password" IDP already exists
idp_exists=$(oc get oauth cluster -o json | jq -r --arg IDP_NAME "$IDP_NAME" '.spec.identityProviders[]? | select(.name == $IDP_NAME)')

if [ "$idp_exists" != "" ]; then

 echo "The IDP '$IDP_NAME' already exists."
  
  # Extract htpasswd file from secret if it doesn't exist locally
  if [ ! -f "$HTPASSWD_FILE" ]; then
    extract_htpasswd
  fi
  
# Retrieve the current htpasswd file from the secret
  oc extract secret/$SECRET_NAME --to=. -n $NAMESPACE --confirm

  PS3="Choose an option: "
  options=("Add a user" "Remove a user" "Change a user's password" "Add a user to cluster-admin" "Remove a user from cluster-admin" "Exit")
  select opt in "${options[@]}"
  do
    case $opt in
      "Add a user")
        add_user
        ;;
      "Remove a user")
        remove_user
        ;;
      "Change a user's password")
        change_password
        ;;
      "Add a user to cluster-admin")
        add_cluster_admin
        ;;
      "Remove a user from cluster-admin")
        remove_cluster_admin
        ;;
      "Exit")
        break
        ;;
      *) echo "Invalid option $REPLY";;
    esac
  done
else
echo "Creating the IDP '$IDP_NAME'..."
  extract_htpasswd  # Attempt to extract htpasswd, in case it's a re-setup
  add_user
  oc create secret generic $SECRET_NAME --from-file=htpasswd=$HTPASSWD_FILE -n $NAMESPACE
fi

# Update the secret in OpenShift with the updated htpasswd file
oc create secret generic $SECRET_NAME --from-file=htpasswd=$HTPASSWD_FILE -n $NAMESPACE --dry-run=client -o yaml | oc apply -f -

# Get the current OAuth configuration
current_oauth_config=$(oc get oauth cluster -o json)

# Update the specific IDP configuration
updated_oauth_config=$(echo $current_oauth_config | jq --arg IDP_NAME "$IDP_NAME" --arg SECRET_NAME "$SECRET_NAME" '
.spec.identityProviders[] |= (select(.name == $IDP_NAME) .htpasswd.fileData.name = $SECRET_NAME)')

# Apply the updated configuration
echo $updated_oauth_config | oc apply -f -

echo "Operation completed. Waiting for authentication pods to restart..."

# Wait for the authentication pods to restart
oc get pods -n $AUTHENTICATION_NAMESPACE -l $POD_LABEL -w

echo "Authentication pods have restarted."

