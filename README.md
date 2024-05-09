# Deployment and Automation with Salt (SaltStack)

_Salt states and relevant files for handling a variety of configuration tasks on minions._

---

The files in this repository were part of an earlier project, and the versions made public were edited for privacy and brevity.
This content is shared in the hope of serving as a quick-reference guide for users who are getting familiar with Salt.

## State Modules Used:

+ `user` and `group`
+ `file`
+ `pkg`, `pkgrepo`, `pip`
+ `cmd`
+ `service`
+ `mysql` modules
+ `cron`
+ `archive`
+ `firewalld`, `selinux`, `sysctl`, `timezone`

## Stack

+ Ubuntu (22.04 Jammy), CentOS Stream (9)
+ Nginx
+ MySQL
+ PHP
+ Wordpress
