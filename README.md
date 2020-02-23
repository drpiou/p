# p
Interactively Manage Your PHP Versions.



## Motivation

Dealing with PHP versions can be painful if you have many different projects which requires each a specific version of PHP to run with Composer. There is a `platform` option in the `composer.json`, but it doesn't cover PHP versions range.

I wanted a final, clean solution, which alows me to copy/paste cli like `composer require <package>` instead of an alias like `composer72 require <package>` to run PHP 7.2.

In my case, I also want to "sync" the version executed by php and composer, for example with Laravel and its artisan command. I were in a situation where `php artisan` was running PHP 7.2 because of the alias created by my MAMP, while `composer` was running PHP 7.1 because of my OS X `/usr/bin/php`, into the same root project.

I'm glad if it helps :)



## Installation

Copy script:

```bash
mv p.sh /usr/local/bin/p
```

Make it executable:

```bash
chmod u+x /usr/local/bin/p
```

Then add into `~/.bash_profile`:

```bash
export P_PREFIX=$HOME/.p
export PATH=$P_PREFIX/bin:$PATH
```

Don't foget to source your `~/.bash_profile`:

```bash
source ~/.bash_profile
```

Done!



## Usage

```
Usage: p [options] [COMMAND] [args]
Commands:
  p <version>                   Link php <version>
  p update <version>            Update installed php <version>
  p run <version> [args ...]    Execute php <version> with [args ...]
  p which <version>             Output path for php <version>
  p rm <version ...>            Remove the given downloaded version(s)
  p prune                       Remove all downloaded versions except the installed version
  p ls                          Output versions
  p ls-remote [version]         Output matching versions available for download
  p uninstall                   Remove the installed p
Options:
  -V, --version                 Output version of p
  -h, --help                    Display help information
  -d, --download                Download <version>
  -P, --path                    Force installation from path
  -H, --homebrew                Force installation from Homebrew
  -S, --silent                  Silent output
  -T, --trace                   Trace output
Aliases:
  update: u
  which: bin
  run: use, as
  ls: list
  lsr: ls-remote
  rm: -
```



With OS X binary, it should looks like something similar to:

```bash
p run test.php

<same as>

php test.php
```



## Configuration

To make it completly transparent, you can add a configuration file under the user folder located at `~/.php-version`:

```
path=          // The main folder where to look at "versioned" folder (eg: php7.2.21)
folder=        // The folder where to look for a {bin} under the "versioned" folder
bin=php        // The bin to find
```



To silently switch the php versions for each project you may have, you can also add the same configuration file under each project folder that will override the user one, named as `.php-version`.



## Use Case

Soon...



### TODO

ext __semver install
ext __select_version install
fix __select_version ctrl+c
remove version
uninstall version
cd hook
