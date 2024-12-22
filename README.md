Forked and adapted from https://github.com/morpht/letsencrypt_drupal

# Let's Encrypt Drupal

Wrapper script for https://github.com/dehydrated-io/dehydrated opinionated towards running in Drupal hosting environments and reporting to Slack. Slack is optional. Let's Encrypt challenge is published trough Drupal using Drush. There is no need to alter webserver settings or upload files.

## What it does

* Installation (TL;DR version)
  * `git clone` this repository to your server
  * Add configuration to your project.
  * Add cron task.
* Every time script gets executed (ideally once a week) it will
  * Self update check.
  * Check if dehydrated-io/dehydrated is available or download it, if needed.
  * [If] There is **no** certificate generated by this script yet.
    * Generate a key pair.
    * Register you with Let's Encrypt.
    * Generate new certificate for you.
  * [If] There **already is** certificate generated by this script.
    * It will check the validity of the certificate.
    * [If] The certificate is valid and not near the expiration date.
      * Post to Slack/Teams that everything is all right.
    * [If] The certificate is about to expire.
      * Renew the certificate.
      * Post to Slack/Teams that everything is all right.
  * (Altering the list of domains in project repository results in generating new certificate.)
  * Upload new certificate to Acquia.
  * Activate the certificate.
  * Post the results to Slack/Teams

## Requirements

* Environment where you can run bash script and setup cron.
* Read access to project root. (accessing config files)
* Permissions to run Drush commands with Drush alias against the site which is accessible via domains listed in `domains_site.env.txt` from internet.
* `git` must available.
* https://www.drupal.org/project/letsencrypt_challenge on target site.

## Installation

These steps are for `prod` environment of PROJECT on Acquia Cloud. Can be easily adapted to other hosting environments.

* `ssh PROJECT.prod@srv-XXXX.devcloud.hosting.acquia.com`
  * (You can get the address on "Servers" tab in Acquia UI)
  * `cd ~`
  * `git clone https://github.com/undp/letsencrypt_drupal.git`
* In project root
  * Add letsencrypt_drupal configuration.
    * `git clone https://github.com/undp/letsencrypt_drupal.git tmp_lea` # Temporarily get the repository to get example configuration files.
    * `cp -r tmp_lea/example_project_config/* .` # Copy the configuration.
    * `rm -rf tmp_lea/`
    * Edit `letsencrypt_drupal/dehydrated/config.sh`
      * You need to set your e-mail. The script provides the rest of defaults needed to get a certificate.
      * You can alter other values as described here: https://github.com/dehydrated-io/dehydrated/blob/master/docs/examples/config
    * Edit `letsencrypt_drupal/domains_undp.env.txt`
      * Rename it based on site alias you are going to be using.
      * For multiple environments create multiple copies of this file.
      * One line, space separated list of domains.
      * First domain will be set as Common name
      * Others are set as SANs
    * Edit `letsencrypt_drupal/config_undp.env.sh`
      * Slack/Teams is optional. If you don't want to use it, just set `$SLACK_WEBHOOK_URL` to empty string.
      * Get your webhook url here: https://my.slack.com/services/new/incoming-webhook/
      * Set the webhook url and target channel variables.
      * Certificate deployment is optional.
        * Fallback is just posting instructions in Slack/Log file.
        * Set the `$CERT_DEPLOY_ENVIRONMENT_UUID` (Environment uuid needs to be aligned with the `env` of the file name.)
    * Multiple environments mean multiple config files. For example `test` and `live`:
      * `config_undp.01test.sh`
      * `config_undp.01live.sh`
      * `domains_undp.01test.txt`
      * `domains_undp.01live.txt`
    * `secrets.settings.php`
      * Should *not* be committed in project repository.
      * Should be placed on Acquia server here: `/mnt/files/undp.01live/secrets.settings.php`
  * Add https://www.drupal.org/project/letsencrypt_challenge module.
    * `composer require drupal/letsencrypt_challenge`
  * Commit and deploy to production.
* In Acquia UI add the Scheduled task
  * Running the task often is not a problem.
  * Ideal is once a week, ideally on Monday morning.
    * Nobody wants to fix certificates on Friday evening :)
    * You should have 60 days of time (with default settings) even if something fails or new manual certificate upload is needed.
  * New job:
    * Job name: `LE renew cert` (just a default, feel free change it)
    * Command: `/home/undp/letsencrypt_drupal/letsencrypt_drupal.sh undp 01live &>> /var/log/sites/${AH_SITE_NAME}/logs/$(hostname -s)/letsencrypt_drupal.log`
    * Command frequency `0 7 * * 1` ( https://crontab.guru/#0_7_*_*_1 )
  * It's good idea to run the command on Acquia manually first time to check if all is OK.
* First script run will post results/instructions to Slack/Teams.
