#!/bin/bash

chmod +t $HOME
cd $HOME/Maildir/.SeekerInc
tar --remove-files -cvzf SeekerInc.$(date +%Y%m%d).tgz SeekerInc
> SeekerInc
chmod -t $HOME
