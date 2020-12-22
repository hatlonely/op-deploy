#!/usr/bin/env bash

function Trac() {
    echo "[TRAC] [$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

function Info() {
    echo "\033[1;32m[INFO] [$(date +"%Y-%m-%d %H:%M:%S")] $1\033[0m"
}

function Warn() {
    echo "\033[1;31m[WARN] [$(date +"%Y-%m-%d %H:%M:%S")] $1\033[0m"
    return 1
}

function Build() {
    cd .. && make image && cd - || return
    docker login --username="${REGISTRY_USERNAME}" --password="${REGISTRY_PASSWORD}" "${REGISTRY_SERVER}"
    docker tag "${REGISTRY_NAMESPACE}/${IMAGE_REPOSITORY}:${IMAGE_TAG}" "${REGISTRY_SERVER}/${REGISTRY_NAMESPACE}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
    docker push "${REGISTRY_SERVER}/${REGISTRY_NAMESPACE}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
}

function SQLTpl() {
    environment=$1
    kubectl run -n "${NAMESPACE}" -it --rm sql --image=mysql:5.7.30 --restart=Never -- \
      mysql -uroot -h"${MYSQL_SERVER}" -p"${MYSQL_ROOT_PASSWORD}" -e "$(cat "tmp/${environment}/create_table.sql")"
}

function CreateNamespaceIfNotExists() {
    kubectl get namespaces "${NAMESPACE}" 2>/dev/null 1>&2 && return 0
    kubectl create namespace "${NAMESPACE}" &&
    Info "create namespace ${NAMESPACE} success" ||
    Warn "create namespace ${NAMESPACE} failed"
}

function CreatePullSecretsIfNotExists() {
    CreateNamespaceIfNotExists || return 1
    kubectl get secret "${PULL_SECRETS}" -n "${NAMESPACE}" 2>/dev/null 1>&2 && return 0
    kubectl create secret docker-registry "${PULL_SECRETS}" \
        --docker-server="${REGISTRY_SERVER}" \
        --docker-username="${REGISTRY_USERNAME}" \
        --docker-password="${REGISTRY_PASSWORD}" \
        --namespace="${NAMESPACE}" &&
    Info "[kubectl create secret docker-registry ${PULL_SECRETS}] success" ||
    Warn "[kubectl create secret docker-registry ${PULL_SECRETS}] failed"
}

function Render() {
    environment=$1
    variable=$2
    sh tpl.sh render "${environment}" "${variable}" || return 1
    # shellcheck source=tmp/$1/environment.sh
    source "tmp/${environment}/environment.sh"
    rm -rf "tmp/${environment}/${NAME}" && cp -r chart/myapp "tmp/${environment}/${NAME}"
    eval "cat > \"tmp/${environment}/${NAME}/Chart.yaml\" <<EOF
$(< "chart/myapp/Chart.yaml")
EOF"
    sh tpl.sh render "${environment}" "${variable}" || return 1
}

function Test() {
    kubectl run -n "${NAMESPACE}" -it --rm "${NAME}" \
      --image="${REGISTRY_SERVER}/${REGISTRY_NAMESPACE}/${IMAGE_REPOSITORY}:${IMAGE_TAG}" \
      --restart=Never \
      -- /bin/bash
}

function AddLabel() {
    node=$1
    kubectl label node "${node}" "${NODE_AFFINITY_LABEL_KEY}=${NODE_AFFINITY_LABEL_VAL}" --overwrite=true
}

function DelLabel() {
    node=$1
    kubectl label node "${node}" "${NODE_AFFINITY_LABEL_KEY}"-
}

function AddTaint() {
    node=$1
    kubectl taint node "${node}" "${TOLERATIONS_TAINT_KEY}=${TOLERATIONS_TAINT_VAL}:NoExecute" --overwrite=true
}

function DelTaint() {
    node=$1
    kubectl taint node "${node}" "${TOLERATIONS_TAINT_KEY}:NoExecute-"
}

function Install() {
    environment=$1
    helm install "${NAME}" -n "${NAMESPACE}" "tmp/${environment}/${NAME}" -f "tmp/${environment}/chart.yaml"
}

function Upgrade() {
    environment=$1
    helm upgrade "${NAME}" -n "${NAMESPACE}" "tmp/${environment}/${NAME}" -f "tmp/${environment}/chart.yaml"
}

function Diff() {
    environment=$1
    helm diff upgrade "${NAME}" -n "${NAMESPACE}" "tmp/${environment}/${NAME}" -f "tmp/${environment}/chart.yaml"
}

function Delete() {
    helm delete "${NAME}" -n "${NAMESPACE}"
}

function Restart() {
    kubectl get pods -n "${NAMESPACE}" | grep "${NAME}" | awk '{print $1}' | xargs kubectl delete pods -n "${NAMESPACE}"
}

function Help() {
    echo "sh deploy.sh <environment> <action>"
    echo "example"
    echo "  sh deploy.sh prod build"
    echo "  sh deploy.sh prod sql"
    echo "  sh deploy.sh prod secret"
    echo "  sh deploy.sh prod render ~/.gomplate/prod.json"
    echo "  sh deploy.sh prod install"
    echo "  sh deploy.sh prod upgrade"
    echo "  sh deploy.sh prod delete"
    echo "  sh deploy.sh prod diff"
    echo "  sh deploy.sh prod test"
    echo "  sh deploy.sh prod addLabel node1"
    echo "  sh deploy.sh prod delLabel node1"
    echo "  sh deploy.sh prod addTaint node1"
    echo "  sh deploy.sh prod delTaint node1"
}

function main() {
    if [ -z "$2" ]; then
        Help
        return 0
    fi

    environment=$1
    action=$2

    if [ "${action}" == "render" ]; then
        Render "${environment}" "$3"
        return 0
    fi

    # shellcheck source=tmp/$1/environment.sh
    source "tmp/$1/environment.sh"

    if [ "${action}" != "build" ] && [ "${K8S_CONTEXT}" != "$(kubectl config current-context)" ]; then
        Warn "context [${K8S_CONTEXT}] not match [$(kubectl config current-context)]"
        return 1
    fi

    case "${action}" in
        "build") Build;;
        "sql") SQLTpl "${environment}";;
        "secret") CreatePullSecretsIfNotExists;;
        "install") Install "${environment}";;
        "upgrade") Upgrade "${environment}";;
        "diff") Diff "${environment}";;
        "addLabel") AddLabel "$3";;
        "delLabel") DelLabel "$3";;
        "addTaint") AddTaint "$3";;
        "delTaint") DelTaint "$3";;
        "delete") Delete;;
        "test") Test;;
        "restart") Restart;;
        *) Help;;
    esac
}

main "$@"
