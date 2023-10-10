#!/bin/bash

# Assicurati di avere yq e oc installati

process_file() {
    local file="$1"
    local filename=$(basename "$file")
    local output_dir="output"
    local output_file="$output_dir/${filename%.yaml}-infra.yaml"

    # Crea la directory di output se non esiste
    mkdir -p "$output_dir"

    # Verifica se il file di output esiste già e chiedi conferma per sovrascriverlo
    if [ -f "$output_file" ]; then
        read -p "Il file $output_file esiste già. Vuoi sovrascriverlo? (y/n) " choice
        case "$choice" in
            y|Y) echo "Sovrascrittura del file $output_file...";;
            *) echo "Saltando il file $file..."; return;;
        esac
    fi

    # Copia il file originale al nuovo file con suffisso -infra
    cp "$file" "$output_file"

    # Estrai le informazioni necessarie dal file YAML
    infrastructure_id=$(yq eval '.metadata.labels."machine.openshift.io/cluster-api-cluster"' "$output_file")
    zone=$(echo $(yq eval '.metadata.name' "$output_file") | awk -F '-worker-' '{print $2}')
    
    # Cambia il nome
    yq eval -i '.metadata.name = "'"$infrastructure_id"'-infra-'"$zone"'"' "$output_file"
    
    # Aggiungi il taint
    yq eval -i '.spec.template.spec.taints += [{"key": "node-role.kubernetes.io/infra", "effect": "NoSchedule"}]' "$output_file"
   
    # Modifica le labels
    yq eval -i '.spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = "infra"' "$output_file"
    yq eval -i '.spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = "infra"' "$output_file"
    yq eval -i '.spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = "'"$infrastructure_id"'-infra-'"$zone"'"' "$output_file"
    yq eval -i '.spec.template.spec.metadata.labels."node-role.kubernetes.io/infra" = ""' "$output_file"
    yq eval -i '.spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = "'"$infrastructure_id"'-infra-'"$zone"'"' "$output_file"
    yq eval -i '.spec.template.spec.metadata.labels."node-role.kubernetes.io/infra" = ""' "$output_file"

    # Rimuovi campi indesiderati e il campo "status"
    yq eval -i 'del(.metadata.creationTimestamp, .metadata.resourceVersion, .metadata.selfLink, .metadata.uid, .status)' "$output_file"

    echo "File $output_file modificato con successo."
}

if [ -z "$1" ]; then
    # Nessuna directory fornita, ottieni MachineSets dal cluster online
    oc get machinesets -l machine.openshift.io/cluster-api-machine-role=worker -o yaml > online_machinesets.yaml
    # Dividi l'YAML combinato in file separati per ogni MachineSet
    csplit -f machine_set_ online_machinesets.yaml '/^---$/' '{*}'
    # Processa ogni file MachineSet separato
    for file in machine_set_*; do
        process_file "$file"
        rm "$file"
    done
else
    DIRECTORY="$1"
    # Itera su tutti i file YAML nella directory fornita
    for file in $DIRECTORY/*.yaml; do
        process_file "$file"
    done
fi

echo "Operazione completata."
