#!/bin/bash

# Check for the presence of infra nodes
infra_nodes=$(oc get nodes -l node-role.kubernetes.io/infra= -o name | grep "node/")

if [ -z "$infra_nodes" ]; then
    echo "There are no infra nodes in the cluster. Exiting."
    exit 1
else
    count=$(echo "$infra_nodes" | wc -l)
    echo "There are $count infra nodes in the cluster:"
    echo "$infra_nodes"
    echo ""
fi

# Ensure you have oc installed and are authenticated to the cluster

move_registry() {
    oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"nodeSelector":{"node-role.kubernetes.io/infra":""}}}'
    echo "Registry moved to infra nodes."
}

move_router() {
    oc patch ingresscontroller default -n openshift-ingress-operator --type merge --patch '{"spec":{"nodePlacement":{"nodeSelector":{"matchLabels":{"node-role.kubernetes.io/infra":""}}}}}'
    echo "Router moved to infra nodes."
}

move_logging() {
    oc patch es/elasticsearch -n openshift-logging --type merge --patch '{"spec":{"nodeSelector":{"node-role.kubernetes.io/infra":""}}}'
    echo "Logging moved to infra nodes."
}

move_monitoring() {
    oc patch prometheus/k8s -n openshift-monitoring --type merge --patch '{"spec":{"nodeSelector":{"node-role.kubernetes.io/infra":""}}}'
    oc patch alertmanager/main -n openshift-monitoring --type merge --patch '{"spec":{"nodeSelector":{"node-role.kubernetes.io/infra":""}}}'
    echo "Monitoring moved to infra nodes."
}

interactive_mode() {
    read -p "Do you want to move the Registry to infra nodes? (y/n) " choice
    [[ "$choice" == "y" || "$choice" == "Y" ]] && move_registry

    read -p "Do you want to move the Router to infra nodes? (y/n) " choice
    [[ "$choice" == "y" || "$choice" == "Y" ]] && move_router

    read -p "Do you want to move the Logging to infra nodes? (y/n) " choice
    [[ "$choice" == "y" || "$choice" == "Y" ]] && move_logging

    read -p "Do you want to move the Monitoring to infra nodes? (y/n) " choice
    [[ "$choice" == "y" || "$choice" == "Y" ]] && move_monitoring
}

# Parameter check
if [ "$#" -eq 0 ]; then
    interactive_mode
else
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --all|-a)
                move_registry
                move_router
                move_logging
                move_monitoring
                shift
                ;;
            --registry)
                move_registry
                shift
                ;;
            --router)
                move_router
                shift
                ;;
            --logging)
                move_logging
                shift
                ;;
            --monitoring)
                move_monitoring
                shift
                ;;
            *)
                echo "Unrecognized option: $1"
                exit 1
                ;;
        esac
    done
fi

echo "Operation completed."

