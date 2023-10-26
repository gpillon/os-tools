#!/bin/bash

# Assicurati di essere loggato in OpenShift e di avere i permessi necessari
oc whoami &>/dev/null
if [ $? -ne 0 ]; then
  echo "Errore: Devi essere loggato in OpenShift."
  exit 1
fi

# Variabili
IDP_NAME="password"
SECRET_NAME="htpasswd-secret"
NAMESPACE="openshift-config"
HTPASSWD_FILE="users.htpasswd"
AUTHENTICATION_NAMESPACE="openshift-authentication"
POD_LABEL="app=oauth-openshift"

# Funzione per aggiungere un utente al ruolo cluster-admin
add_cluster_admin() {
  echo "Utenti esistenti:"
  awk -F: '{ print $1 }' $HTPASSWD_FILE
  read -p "Inserisci il nome utente da aggiungere a cluster-admin: " username
  # Verifica se l'utente esiste
  if ! grep -q "^$username:" $HTPASSWD_FILE; then
    echo "L'utente $username non esiste."
    return
  fi
  oc adm policy add-cluster-role-to-user cluster-admin $username
  echo "L'utente $username è stato aggiunto al ruolo cluster-admin."
}

# Funzione per rimuovere un utente dal ruolo cluster-admin
remove_cluster_admin() {
  read -p "Inserisci il nome utente da rimuovere da cluster-admin: " username
  oc adm policy remove-cluster-role-from-user cluster-admin $username
  echo "L'utente $username è stato rimosso dal ruolo cluster-admin."
}

# Funzione per gestire l'aggiunta di un nuovo utente
add_user() {
  read -p "Inserisci il nome utente: " username
  # Verifica se l'utente esiste già
  if grep -q "^$username:" $HTPASSWD_FILE; then
    read -p "L'utente esiste già. Vuoi aggiornare la password? (y/n): " update
    if [ "$update" != "y" ]; then
      echo "Operazione annullata."
      return
    fi
  fi
  read -s -p "Inserisci la password: " password
  echo
  htpasswd -B -b $HTPASSWD_FILE $username $password
}

# Funzione per gestire la rimozione di un utente
remove_user() {
  echo "Utenti esistenti:"
  awk -F: '{ print $1 }' $HTPASSWD_FILE
  read -p "Inserisci il nome utente da rimuovere: " username
  # Verifica se l'utente esiste
  if ! grep -q "^$username:" $HTPASSWD_FILE; then
    echo "L'utente $username non esiste."
    return
  fi
  htpasswd -D $HTPASSWD_FILE $username
}

# Funzione per gestire la modifica della password di un utente
change_password() {
  echo "Utenti esistenti:"
  awk -F: '{ print $1 }' $HTPASSWD_FILE
  read -p "Inserisci il nome utente per cui modificare la password: " username
  # Verifica se l'utente esiste
  if ! grep -q "^$username:" $HTPASSWD_FILE; then
    echo "L'utente $username non esiste."
    return
  fi
  read -s -p "Inserisci la nuova password: " password
  echo
  htpasswd -b $HTPASSWD_FILE $username $password
}


# Controlla se l'IDP "password" esiste già
idp_exists=$(oc get oauth cluster -o json | jq -r --arg IDP_NAME "$IDP_NAME" '.spec.identityProviders[]? | select(.name == $IDP_NAME)')

if [ "$idp_exists" != "" ]; then
  echo "L'IDP '$IDP_NAME' esiste già."
  # Recupera il file htpasswd corrente dal secret
  oc extract secret/$SECRET_NAME --to=. -n $NAMESPACE --confirm

  PS3="Scegli un'opzione: "
  options=("Aggiungi un utente" "Rimuovi un utente" "Modifica la password di un utente" "Aggiungi un utente a cluster-admin" "Rimuovi un utente da cluster-admin" "Esci")
  select opt in "${options[@]}"
  do
    case $opt in
      "Aggiungi un utente")
        add_user
        ;;
      "Rimuovi un utente")
        remove_user
        ;;
      "Modifica la password di un utente")
        change_password
        ;;
      "Aggiungi un utente a cluster-admin")
        add_cluster_admin
        ;;
      "Rimuovi un utente da cluster-admin")
        remove_cluster_admin
        ;;
      "Esci")
        break
        ;;
      *) echo "Opzione non valida $REPLY";;
    esac
  done
else
  echo "Creazione dell'IDP '$IDP_NAME'..."
  add_user
  oc create secret generic $SECRET_NAME --from-file=htpasswd=$HTPASSWD_FILE -n $NAMESPACE

  # Crea l'IDP
  oc apply -f - <<EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: $IDP_NAME
    challenge: true
    login: true
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: $SECRET_NAME
EOF

  echo "Configurazione completata con successo."
fi

# Aggiorna il secret in OpenShift con il file htpasswd aggiornato
oc create secret generic $SECRET_NAME --from-file=htpasswd=$HTPASSWD_FILE -n $NAMESPACE --dry-run=client -o yaml | oc apply -f -

echo "Operazione completata. In attesa che i pod di autenticazione si riavviino..."

# Attendi che i pod di autenticazione si riavviino
oc get pods -n $AUTHENTICATION_NAMESPACE -l $POD_LABEL -w

echo "I pod di autenticazione sono stati riavviati."
