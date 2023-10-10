#!/bin/bash

# Ensure you have yq and oc installed

process_file() {
    local file="$1"
    local filename=$(basename "$file")
    local output_dir="output"
    local output_file="$output_dir/${filename%.yaml}-infra.yaml"

    # Create the output directory if it doesn't exist
    mkdir -p "$output_dir"

    # Check if the output file already exists and ask for confirmation to overwrite it
    if [ -f "$output_file" ]; then
        read -p "The file $output_file already exists. Do you want to overwrite it? (y/n) " choice
        case "$choice" in
            y|Y) echo "Overwriting the file $output_file...";;
            *) echo "Skipping the file $file..."; return;;
        esac
    fi

    # Copy the original file to the new file with -infra suffix
    cp "$file" "$output_file"

    # Extract necessary information from the YAML file
    infrastructure_id=$(yq eval '.metadata.labels."machine.openshift.io/cluster-api-cluster"' "$output_file")
    zone=$(echo $(yq eval '.metadata.name' "$output_file") | awk -F '-worker-' '{print $2}')
    
    # Change the name
    yq eval -i '.metadata.name = "'"$infrastructure_id"'-infra-'"$zone"'"' "$output_file"
    
    # Add the taint
    yq eval -i '.spec.template.spec.taints += [{"key": "node-role.kubernetes.io/infra", "effect": "NoSchedule"}]' "$output_file"
   
    # Modify the labels
    yq eval -i '.spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = "infra"' "$output_file"
    yq eval -i '.spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = "infra"' "$output_file"
    yq eval -i '.spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = "'"$infrastructure_id"'-infra-'"$zone"'"' "$output_file"
    yq eval -i '.spec.template.spec.metadata.labels."node-role.kubernetes.io/infra" = ""' "$output_file"
    yq eval -i '.spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = "'"$infrastructure_id"'-infra-'"$zone"'"' "$output_file"
    yq eval -i '.spec.template.spec.metadata.labels."node-role.kubernetes.io/infra" = ""' "$output_file"

    # Remove unwanted fields and the "status" field
    yq eval -i 'del(.metadata.creationTimestamp, .metadata.resourceVersion, .metadata.selfLink, .metadata.uid, .status)' "$output_file"

    echo "File $output_file successfully modified."
}

if [ -z "$1" ]; then
    # No directory provided, get MachineSets from the online cluster
    oc get machinesets -l machine.openshift.io/cluster-api-machine-role=worker -o yaml > online_machinesets.yaml
    # Split the combined YAML into separate files for each MachineSet
    csplit -f machine_set_ online_machinesets.yaml '/^---$/' '{*}'
    # Process each separate MachineSet file
    for file in machine_set_*; do
        process_file "$file"
        rm "$file"
    done
else
    DIRECTORY="$1"
    # Iterate over all YAML files in the provided directory
    for file in $DIRECTORY/*.yaml; do
        process_file "$file"
    done
fi

echo "Operation completed."

