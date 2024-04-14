#!/bin/bash

download_helm_charts() {
  # Extract the chart repository URLs and versions from the Porter manifest
  local -A repo_urls=()
  local -A chart_versions=()
  local chart_names=()

  # Extract the chart repository URLs from the mixins section
  while read -r repo_name repo_url; do
      repo_urls["$repo_name"]="$repo_url"
      helm repo add "${repo_name}" "${repo_url}"
  done < <(yq e '.mixins[] | .helm3.repositories | to_entries | .[] | "\(.key) \(.value.url)"' porter.yaml)

  helm repo update

  # Extract the chart names from the install section
  while read -r chart_name; do
      chart_names+=( $chart_name )
  done < <(yq e '.install[] | .helm3.chart' porter.yaml)

  # Extract the chart version information from the parameters section
  while read -r chart_version_name chart_version_value; do
      chart_versions["$chart_version_name"]="$chart_version_value"
  done < <(yq e '.parameters[] | select(.name == "*helm-chart-version") | "\(.name) \(.default)"' porter.yaml)

  # Extract the chart names and versions from the install section
  while read -r chart_info version_info; do
      local chart_repo="${chart_info%%/*}"
      local chart_name="${chart_info#*/}"
      local version_info=$(echo "${version_info}" | sed -e 's/^\$//')
      local chart_version="${chart_versions[$version_info]}"
      helm pull "${chart_repo}/${chart_name}" --version "${chart_version}" -d charts
  done < <(yq e '.install[].helm3 | "\(.chart) \(.version)"' porter.yaml)
}

do_bundle() {
  # Switch to the distribution directory
  pushd dist > /dev/null || exit 1

  echo "Downloading Porter CLI..."
  download_porter_cli

  # Build the bundle
  porter build --dir ../
  porter publish --force --dir ../ --reference ${BUNDLE_REGISTRY}/${BUNDLE_NAME}:v${BUNDLE_VERSION}
  porter archive ${BUNDLE_NAME}.tgz --reference ${BUNDLE_REGISTRY}/${BUNDLE_NAME}:v${BUNDLE_VERSION}

  # Package the CLI and the bundle in a distributable archive
  tar -czf ./${BUNDLE_NAME}-bundle.tar.gz porter ${BUNDLE_NAME}.tgz
}

download_porter_cli() {
  if [ "$PORTER_OS" == "linux" ]; then
    PORTER_FILENAME="porter-linux-amd64"
  elif [ "$PORTER_OS" == "darwin" ]; then
    PORTER_FILENAME="porter-darwin-amd64"
  elif [ "$PORTER_OS" == "windows" ]; then
    PORTER_FILENAME="porter-windows-amd64.exe"
  else
    echo "Unsupported operating system: $PORTER_OS"
    exit 1
  fi

  # Download the Porter CLI binary for use on systems that do not have Porter installed
  curl -L https://cdn.porter.sh/v${PORTER_VERSION}/$PORTER_FILENAME -o ./porter
  chmod +x ./porter
}

init() {
  # Get the latest Porter version
  PORTER_VERSION=$(porter version | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+')

  # Get the Porter bundle name
  BUNDLE_NAME=$(cat ./porter.yaml | grep "name:" | head -n 1 | cut -d':' -f2 | xargs)
  BUNDLE_VERSION=$(cat ./porter.yaml | grep "version:" | head -n 1 | cut -d':' -f2 | xargs)
  BUNDLE_REGISTRY=$(grep -E '^registry:' porter.yaml | sed 's/"//g' | cut -d':' -f2,3 | xargs)

  # Create the "charts" directory if it doesn't exist
  mkdir -p charts
  touch charts/tmp
  rm charts/*

  # Create the "dist" directory if nonexistent
  mkdir -p dist

  # Clear any previous distribution files
  rm -rf dist/*
}

finish() {
  popd > /dev/null
}

PORTER_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
PORTER_OS=${PORTER_OS:-linux}
case "$PORTER_OS" in
  linux*)     PORTER_OS=linux;;
  darwin*)    PORTER_OS=darwin;;
  cygwin*)    PORTER_OS=windows;;
  mingw*)     PORTER_OS=windows;;
  *)          echo "Unsupported operating system: $(uname -s)" && exit 1
esac

# Prepare for script actions
echo "Initializing..."
init

# Download the helm charts
echo "Downloading helm charts..."
download_helm_charts

# Build and export the bundle to a portable file
echo "Creating and exporting bundle..."
do_bundle

echo "Finished..."
finish
