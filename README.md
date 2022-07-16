# Shutter SFTP UI plugin

Plugin to upload your screenshots via SFTP protocol.

This plugin has a GUI for managing configurations.

# Installation

Plugin uses [Net::SFTP::Foreign](https://metacpan.org/pod/Net::SFTP::Foreign), so we need to install it.

For Ubuntu is will be:

```bash
$ sudo apt install libnet-sftp-foreign-perl
```

To install, place the plugin file in the plugins directory and set the execution permissions:

```bash
$ cd /usr/share/shutter/resources/system/upload_plugins/upload/
$ sudo wget https://raw.githubusercontent.com/elivin/shutter-sftp-ui/master/src/ShutterSftpUI.pm
$ sudo chmod +x ShutterSftpUI.pm
```

# TODO list

- [x] Uploading files by sftp
- [x] Configuration GUI: edit current configuration
- [ ] Configuration GUI: add new configuration option
- [ ] Configuration GUI: remove configuration option
- [ ] Configuration GUI: split password-based and key-based authentication in the edit form
- [ ] Configuration GUI: the "test connection" button
- [x] Configuration GUI: save current configuration choice for session
