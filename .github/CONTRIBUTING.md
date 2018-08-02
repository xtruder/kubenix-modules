# How to contribute

Note: contributing implies licensing those contributions
under the terms of [COPYING](../COPYING), which is an MIT-like license.

## Opening issues

* Make sure you have a [GitHub account](https://github.com/signup/free)
* [Submit an issue](https://github.com/xtruder/kubenix-modules/issues) - assuming one does not already exist.
  * Clearly describe the issue including steps to reproduce when it is a bug.
  * Include information about module that issue affects
  * Include information what version of kubenix-services issue happend in.

## Submitting changes

* Format the commit messages in the following way:

  ```
  (module-name | images/<image> | tests/<test> | nixpkgs): (from -> to | add module | refactor | etc)

  (Motivation for change. Additional information.)
  ```

  Examples:

  * nixpkgs: update to aabbccdd
  * nginx: add module
  * image/confluent: fix image

## Writing good commit messages

In addition to writing properly formatted commit messages, it's important to include relevant information so other developers can later understand *why* a change was made. While this information usually can be found by digging code, mailing list archives, pull request discussions or upstream changes, it may require a lot of work.

For image version upgrades and such a one-line commit message is usually sufficient.
