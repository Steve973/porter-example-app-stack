#!/bin/bash

# Download the Porter CLI binary
PORTER_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
PORTER_OS=${PORTER_OS:-linux}
case "$PORTER_OS" in
  linux*)     PORTER_OS=linux;;
  darwin*)    PORTER_OS=darwin;;
  cygwin*)    PORTER_OS=windows;;
  mingw*)     PORTER_OS=windows;;
  *)          echo "Unsupported operating system: $(uname -s)" && exit 1
esac

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

# Get the latest Porter version
PORTER_VERSION=$(porter version | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+')

# Get the Porter bundle name
BUNDLE_NAME=$(cat ./porter.yaml | grep "name:" | head -n 1 | cut -d':' -f2 | xargs)
BUNDLE_VERSION=$(cat ./porter.yaml | grep "version:" | head -n 1 | cut -d':' -f2 | xargs)
BUNDLE_REGISTRY=$(grep -E '^registry:' porter.yaml | sed 's/"//g' | cut -d':' -f2,3 | xargs)

# Create the "dist" directory if nonexistent
mkdir -p dist

# Switch to the distribution directory
pushd dist || exit 1

# Clear any previous distribution files
rm -rf *

# Download the Porter CLI binary for use on systems that do not have Porter installed
curl -L https://cdn.porter.sh/v${PORTER_VERSION}/$PORTER_FILENAME -o ./porter
chmod +x ./porter

# Build the bundle
porter build --dir ../
porter publish --force --dir ../ --reference ${BUNDLE_REGISTRY}/${BUNDLE_NAME}:v${BUNDLE_VERSION}
porter archive ${BUNDLE_NAME}.tgz --reference ${BUNDLE_REGISTRY}/${BUNDLE_NAME}:v${BUNDLE_VERSION}

# Package the CLI and the bundle in a distributable archive
tar -czf ./${BUNDLE_NAME}-bundle.tar.gz porter ${BUNDLE_NAME}.tgz

popd
