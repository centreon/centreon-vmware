#!/bin/bash

VERSION="$3"
BULLSEYEPACKAGES=`echo *.deb`

for i in $BULLSEYEPACKAGES
do
  echo "Sending $i\n"
  curl -u \"$1:$2\" -H "Content-Type: multipart/form-data" --data-binary \"@/$i\" "https://apt.centreon.com/repository/$VERSION"
done