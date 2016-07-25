# GitExplorer

[![Build Status](https://travis-ci.org/alexrochas/git-explorer.svg?branch=master)](https://travis-ci.org/alexrochas/git-explorer)
[![Gem Version](https://badge.fury.io/rb/git_explorer.svg)](https://badge.fury.io/rb/git_explorer)
![](http://ruby-gem-downloads-badge.herokuapp.com/git_explorer)


GitExplorer comes from the necessity of get the status of all my local repositories. This tool will scan all your projects searching for git repositories and extract the project name, status and files unstaged.

## Installation

Linux:

```sh
~$ gem install git_explorer
```

## Usage example

Start explore with:
```bash
~$ git-explore <root_path>
```

All your git repositories from <root_path> will be scanned and the output will be similar to:
```
project <project_name> is up_to_date on branch master -> []
project <project_name> is up_to_date on branch master -> []
project <project_name> is not_staged on branch  -> ["<file_name>", "<file_name>", "<file_name>"]
```

## Release History

* 0.1.0
    * Work in progress.

## Meta

Alex Rocha - [about.me](http://about.me/alex.rochas)

