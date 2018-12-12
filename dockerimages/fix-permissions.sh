#!/bin/bash

for var in "$@"
do
    chgrp -R 0 $var
    chmod -R g=u $var
done
