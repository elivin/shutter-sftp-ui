#! /usr/bin/env perl
###################################################
#
#  Copyright (C) 2022 Ivan Zverev <ffsjp@yandex.ru>
#
#  This file is part of Shutter.
#
#  Shutter is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  Shutter is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with Shutter; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
###################################################

package ShutterSftpUI;

use lib $ENV{'SHUTTER_ROOT'}.'/share/shutter/resources/modules';

use utf8;
use strict;
use POSIX qw/setlocale/;
use Locale::gettext;
use Glib qw/TRUE FALSE/;
use Data::Dumper;

use Shutter::Upload::Shared;
our @ISA = qw(Shutter::Upload::Shared);

my $d = Locale::gettext->domain("shutter-plugins");
$d->dir( $ENV{'SHUTTER_INTL'} );

my %upload_plugin_info = (
	'module'                        => "ShutterSftpUI",
	'url'                           => "http://shutter-sftp.ffsjp.ru/",
	'registration'                  => "",
	'name'                          => "ShutterSftpUI",
	'description'                   => "Upload screenshots by sftp (UI version)",
	'supports_anonymous_upload'     => TRUE,
	'supports_authorized_upload'    => TRUE,
	'supports_oauth_upload'         => FALSE,
);

binmode(STDOUT, ":utf8");
if (exists $upload_plugin_info{$ARGV[0]}) {
	print $upload_plugin_info{$ARGV[0]};
	exit;
}

my $no_gui = 0;


sub new {
	my $class = shift;

	#call constructor of super class (host, debug_cparam, shutter_root, gettext_object, main_gtk_window, ua)
	my $self = $class->SUPER::new( shift, shift, shift, shift, shift, shift );

	bless $self, $class;
	return $self;
}

sub init {
	my $self = shift;

	use Net::SFTP::Foreign;
	use JSON;
	use Path::Class;
	use File::Basename qw(basename);

	$Net::SFTP::Foreign::debug = -1;

	$self->{_config} = {};
	$self->{_config_file} = file($ENV{'HOME'} . '/.config/shutter-sftp-ui.json');

	if (-f $self->{_config_file}) {
		eval { $self->{_config} = decode_json($self->{_config_file}->slurp); };
	} else {
		$self->{_config}->{conf_num} = 0;
		$self->{_config}->{configurations} = [];
		$self->save_config;
	}

	return $self->setup;
}

sub save_config {
	my $self = shift;

	$self->{_config_file}->openw->print(encode_json($self->{_config}));

	return TRUE;
}

sub add_configuration {
	my $self = shift;

	my $nsd = Shutter::App::SimpleDialogs->new;

	my $n_name = 'configuration name';
	my $n_name_entry = Gtk3::Entry->new();
	$n_name_entry->signal_connect(
		changed => sub {
			$n_name = $n_name_entry->get_text;
		}
	);

	my $n_host = 'site.com';
	my $n_host_entry = Gtk3::Entry->new();
	$n_host_entry->signal_connect(
		changed => sub {
			$n_host = $n_host_entry->get_text;
		}
	);

	my $n_username = 'username';
	my $n_username_entry = Gtk3::Entry->new();
	$n_username_entry->signal_connect(
		changed => sub {
			$n_username = $n_username_entry->get_text;
		}
	);

	my $n_key = '~/.ssh/id_rsa';
	my $n_key_entry = Gtk3::Entry->new();
	$n_key_entry->signal_connect(
		changed => sub {
			$n_key = $n_key_entry->get_text;
		}
	);

	my $n_pass = 'passphrase';
	my $n_pass_entry = Gtk3::Entry->new();
	$n_pass_entry->signal_connect(
		changed => sub {
			$n_pass = $n_pass_entry->get_text;
		}
	);

	my $response = $nsd->dlg_info_message(
		$d->get("Please add new SFTP configuration"),
		$d->get("Add SFTP configuration"),
		'gtk-cancel',
		'gtk-apply',
		undef,
		undef,
		undef,
		undef,
		undef,
		undef,
		undef,
		$n_host_entry,
		$n_username_entry,
	);
	
	if ($response == 20) {
		return TRUE;
	}

	return FALSE;
}

sub unsafe_setup {
	my $self = shift;

	if (scalar(@{$self->{_config}->{configurations}}) == 0) {
		$self->{_config}->{configurations}[0] = {
			'name'       => 'Unnamed',
			'host'       => 'host.com',
			'port'       => '22',
			'username'   => 'user',
			'password'   => '',
			'key'        => '~/.ssh/id_ed25519',
			'passphrase' => 'pass',
			'directory'  => '/home/user/files',
			'link'       => 'https://host.com/screenshots',
		};
		$self->save_config;
	}

	my $plugin_dialog = Gtk3::Dialog->new(
		$d->get("SFTP configuration"),
		$self->{main_gtk_window},
		[qw/modal destroy-with-parent/]
	);
	$plugin_dialog->set_size_request(450, -1);
	$plugin_dialog->set_resizable(TRUE);

	# buttons
	my $run_btn = Gtk3::Button->new_with_mnemonic($d->get("Upload"));
	$run_btn->set_image(Gtk3::Image->new_from_stock('gtk-execute', 'button'));
	$run_btn->set_can_default(TRUE);

	$plugin_dialog->add_button('gtk-cancel', 'reject');
	$plugin_dialog->add_action_widget($run_btn, 'accept');

	# configurations
	my $model = Gtk3::ListStore->new(
		'Glib::String',  # name
	);

	for my $c (@{$self->{_config}->{configurations}}) {
		$model->set(
			$model->append,
			0, $c->{'name'} || 'Unnamed',
		);
	}

	my $conf_box = Gtk3::ComboBox->new_with_model($model);
	my $renderer_host = Gtk3::CellRendererText->new;
	$conf_box->pack_start($renderer_host, FALSE);
	$conf_box->add_attribute($renderer_host, text => 0);
	$conf_box->set_active($self->{_config}->{conf_num} || 0);

	# ----- EDIT FORM ----- #
	my $edit_btn = Gtk3::Button->new_with_mnemonic($d->get("Edit"));
	$edit_btn->signal_connect(
		'clicked' => sub {
			my $edit_conf = $self->{_config}->{configurations}[$conf_box->get_active];

			my $edit_dialog = Gtk3::Dialog->new(
				$d->get("SFTP configuration edit"),
				$plugin_dialog,
				[qw/modal destroy-with-parent/]
			);
			$edit_dialog->set_size_request(450, -1);
			$edit_dialog->set_resizable(TRUE);

			$edit_dialog->add_button('gtk-cancel', 'reject');
			$edit_dialog->add_button('gtk-save', 'accept');

			my $edit_vbox = Gtk3::VBox->new(FALSE, 5);

			# -- edit field: name
			my $cf_name_hbox = Gtk3::HBox->new(FALSE, 0);
			my $cf_name_tt = 'Visible configuration name';
			my $cf_name_label =  Gtk3::Label->new($d->get("Configuration name") . ":");
			$cf_name_label->set_tooltip_text($cf_name_tt);
			my $cf_name_input = Gtk3::Entry->new;
			$cf_name_input->set_text($edit_conf->{'name'} || '');
			$cf_name_input->set_tooltip_text($cf_name_tt);

			$cf_name_hbox->pack_start($cf_name_label, FALSE, TRUE, 10);
			$cf_name_hbox->pack_start($cf_name_input, TRUE, TRUE, 10);
			$edit_vbox->pack_start($cf_name_hbox, FALSE, FALSE, 3);
			# -- edit field: name

			# -- edit field: host
			my $cf_host_hbox = Gtk3::HBox->new(FALSE, 0);
			my $cf_host_tt = 'Host name: host.com';
			my $cf_host_label =  Gtk3::Label->new($d->get("Host") . ":");
			$cf_host_label->set_tooltip_text($cf_host_tt);
			my $cf_host_input = Gtk3::Entry->new;
			$cf_host_input->set_text($edit_conf->{'host'} || '');
			$cf_host_input->set_tooltip_text($cf_host_tt);

			$cf_host_hbox->pack_start($cf_host_label, FALSE, TRUE, 10);
			$cf_host_hbox->pack_start($cf_host_input, TRUE, TRUE, 10);
			$edit_vbox->pack_start($cf_host_hbox, FALSE, FALSE, 3);
			# -- edit field: host

			# -- edit field: port
			my $cf_port_hbox = Gtk3::HBox->new(FALSE, 0);
			my $cf_port_tt = '22 by default';
			my $cf_port_label =  Gtk3::Label->new($d->get("Port") . ":");
			$cf_port_label->set_tooltip_text($cf_port_tt);
			my $cf_port_input = Gtk3::Entry->new;
			$cf_port_input->set_text($edit_conf->{'port'} || '');
			$cf_port_input->set_tooltip_text($cf_port_tt);

			$cf_port_hbox->pack_start($cf_port_label, FALSE, TRUE, 10);
			$cf_port_hbox->pack_start($cf_port_input, TRUE, TRUE, 10);
			$edit_vbox->pack_start($cf_port_hbox, FALSE, FALSE, 3);
			# -- edit field: port

			# -- edit field: username
			my $cf_username_hbox = Gtk3::HBox->new(FALSE, 0);
			my $cf_username_tt = 'Username';
			my $cf_username_label =  Gtk3::Label->new($d->get("Username") . ":");
			$cf_username_label->set_tooltip_text($cf_username_tt);
			my $cf_username_input = Gtk3::Entry->new;
			$cf_username_input->set_text($edit_conf->{'username'} || '');
			$cf_username_input->set_tooltip_text($cf_username_tt);

			$cf_username_hbox->pack_start($cf_username_label, FALSE, TRUE, 10);
			$cf_username_hbox->pack_start($cf_username_input, TRUE, TRUE, 10);
			$edit_vbox->pack_start($cf_username_hbox, FALSE, FALSE, 3);
			# -- edit field: username

			# -- edit field: password
			my $cf_password_hbox = Gtk3::HBox->new(FALSE, 0);
			my $cf_password_tt = 'Set it blank if you want to use key';
			my $cf_password_label =  Gtk3::Label->new($d->get("Password") . ":");
			$cf_password_label->set_tooltip_text($cf_password_tt);
			my $cf_password_input = Gtk3::Entry->new;
			$cf_password_input->set_text($edit_conf->{'password'} || '');
			$cf_password_input->set_tooltip_text($cf_password_tt);
			$cf_password_input->set_visibility(FALSE);

			$cf_password_hbox->pack_start($cf_password_label, FALSE, TRUE, 10);
			$cf_password_hbox->pack_start($cf_password_input, TRUE, TRUE, 10);
			$edit_vbox->pack_start($cf_password_hbox, FALSE, FALSE, 3);
			# -- edit field: password

			# -- edit field: key
			my $cf_key_hbox = Gtk3::HBox->new(FALSE, 0);
			my $cf_key_tt = 'Path to private key file';
			my $cf_key_label =  Gtk3::Label->new($d->get("Key") . ":");
			$cf_key_label->set_tooltip_text($cf_key_tt);
			my $cf_key_input = Gtk3::Entry->new;
			$cf_key_input->set_text($edit_conf->{'key'} || '');
			$cf_key_input->set_tooltip_text($cf_key_tt);

			$cf_key_hbox->pack_start($cf_key_label, FALSE, TRUE, 10);
			$cf_key_hbox->pack_start($cf_key_input, TRUE, TRUE, 10);
			$edit_vbox->pack_start($cf_key_hbox, FALSE, FALSE, 3);
			# -- edit field: key

			# -- edit field: passphrase
			my $cf_passphrase_hbox = Gtk3::HBox->new(FALSE, 0);
			my $cf_passphrase_tt = 'Passphrase for key, blank if key has no passphrase';
			my $cf_passphrase_label =  Gtk3::Label->new($d->get("Passphrase") . ":");
			$cf_passphrase_label->set_tooltip_text($cf_passphrase_tt);
			my $cf_passphrase_input = Gtk3::Entry->new;
			$cf_passphrase_input->set_text($edit_conf->{'passphrase'} || '');
			$cf_passphrase_input->set_tooltip_text($cf_passphrase_tt);
			$cf_passphrase_input->set_visibility(FALSE);

			$cf_passphrase_hbox->pack_start($cf_passphrase_label, FALSE, TRUE, 10);
			$cf_passphrase_hbox->pack_start($cf_passphrase_input, TRUE, TRUE, 10);
			$edit_vbox->pack_start($cf_passphrase_hbox, FALSE, FALSE, 3);
			# -- edit field: passphrase

			# -- edit field: directory
			my $cf_directory_hbox = Gtk3::HBox->new(FALSE, 0);
			my $cf_directory_tt = 'Directory on remote server';
			my $cf_directory_label =  Gtk3::Label->new($d->get("Directory") . ":");
			$cf_directory_label->set_tooltip_text($cf_directory_tt);
			my $cf_directory_input = Gtk3::Entry->new;
			$cf_directory_input->set_text($edit_conf->{'directory'} || '');
			$cf_directory_input->set_tooltip_text($cf_directory_tt);

			$cf_directory_hbox->pack_start($cf_directory_label, FALSE, TRUE, 10);
			$cf_directory_hbox->pack_start($cf_directory_input, TRUE, TRUE, 10);
			$edit_vbox->pack_start($cf_directory_hbox, FALSE, FALSE, 3);
			# -- edit field: directory

			# -- edit field: link
			my $cf_link_hbox = Gtk3::HBox->new(FALSE, 0);
			my $cf_link_tt = 'Base link without last slash (/)';
			my $cf_link_label =  Gtk3::Label->new($d->get("Link") . ":");
			$cf_link_label->set_tooltip_text($cf_link_tt);
			my $cf_link_input = Gtk3::Entry->new;
			$cf_link_input->set_text($edit_conf->{'link'} || '');
			$cf_link_input->set_tooltip_text($cf_link_tt);

			$cf_link_hbox->pack_start($cf_link_label, FALSE, TRUE, 10);
			$cf_link_hbox->pack_start($cf_link_input, TRUE, TRUE, 10);
			$edit_vbox->pack_start($cf_link_hbox, FALSE, FALSE, 3);
			# -- edit field: link

			$edit_dialog->get_child->add($edit_vbox);
			$edit_dialog->show_all;

			my $edit_response = $edit_dialog->run;

			if ($edit_response eq 'accept') {
				$edit_conf->{'name'} = $cf_name_input->get_text;
				$edit_conf->{'host'} = $cf_host_input->get_text;
				$edit_conf->{'port'} = $cf_port_input->get_text;
				$edit_conf->{'username'} = $cf_username_input->get_text;
				$edit_conf->{'password'} = $cf_password_input->get_text;
				$edit_conf->{'key'} = $cf_key_input->get_text;
				$edit_conf->{'passphrase'} = $cf_passphrase_input->get_text;
				$edit_conf->{'directory'} = $cf_directory_input->get_text;
				$edit_conf->{'link'} = $cf_link_input->get_text;
				my $cur_iter = $conf_box->get_active_iter;
				$model->set($cur_iter, 0, $edit_conf->{'name'});

				$self->save_config;
			}

			$edit_dialog->destroy();
		}
	);
	# ----- END EDIT FORM ----- #

	my $no_gui_check = Gtk3::CheckButton->new_with_label($d->get("Save current configuration choice for session"));

	# layouts
	my $conf_vbox1 = Gtk3::VBox->new(FALSE, 5);
	my $conf_hbox = Gtk3::HBox->new(FALSE, 5);

	$conf_hbox->pack_start(Gtk3::Label->new($d->get("Choose configuration") . ":"), FALSE, FALSE, 6);
	$conf_hbox->pack_start($conf_box, TRUE, TRUE, 0);
	$conf_hbox->pack_start($edit_btn, FALSE, FALSE, 0);

	$conf_vbox1->pack_start($conf_hbox, FALSE, FALSE, 3);
	$conf_vbox1->pack_start($no_gui_check, FALSE, FALSE, 3);

	$plugin_dialog->get_child->add($conf_vbox1);
	$plugin_dialog->show_all;

	my $plugin_response = $plugin_dialog->run;
	$plugin_dialog->destroy();

	if ($plugin_response eq 'accept') {
		$self->{_config}->{conf_num} = $conf_box->get_active;
		$self->{_no_gui_status} = $no_gui_check->get_active;

		print "\n\n\n\n\n";
		print $self->{_no_gui_status};
		print "\n\n\n\n\n";

		return TRUE;
	}

	return FALSE;
}

sub setup {
	my $self = shift;
	my $result = FALSE;

	print "\n\n!!! ShutterSftpUI setup no GUI !!!\n";
	print     "!!! -------------------------- !!!\n\n";
	print $no_gui;
	print   "\n!!! -------------------------- !!!\n\n";

	if ($no_gui == 1) {
		return TRUE;
	}

	eval {
		$result = $self->unsafe_setup;
		1;
	} or do {
		my $eval_error= $@ || "Undefined error";

		print "\n\n!!! ShutterSftpUI plugin error !!!\n";
		print     "!!! -------------------------- !!!\n\n";
		print $eval_error;
		print   "\n!!! -------------------------- !!!\n\n";

		my $error_dialog = Shutter::App::SimpleDialogs->new;
		$error_dialog->dlg_info_message(
			$d->get($eval_error),
			$d->get("SFTP plugin error"),
			undef,
			'gtk-apply',
			undef,
			undef,
			undef,
			undef,
			undef,
			undef,
			undef,
			undef,
		);
	};

	return $result;
}

sub unsafe_upload {
	my ( $self, $upload_filename, $username, $password ) = @_;

	my $current_conf = $self->{_config}->{configurations}[$self->{_config}->{conf_num} || 0];

	# you can set username and password in config file
	$username = $current_conf->{'username'} || $username;
	$password = $current_conf->{'password'} || $password;

	#store as object vars
	my $remote_file = $current_conf->{'directory'} . '/' . basename($upload_filename);
	my $key = $current_conf->{'key'} || '';
	my $passphrase = $current_conf->{'passphrase'} || '';
	my $link = $current_conf->{'link'} . '/' . basename($upload_filename);
 
	utf8::encode $upload_filename;
	utf8::encode $password;
	utf8::encode $username;

	my %ssh_opts = (
		'user' => $username,
		'timeout' => '10',
	);

	if ($self->{_debug_cparam}) {
		$ssh_opts{'more'} = '-v';
	}

	if( $password ne "" ) {
		$ssh_opts{'password'} = $password;
	}
	if( $key ne "" ) {
		$ssh_opts{'key_path'} = $key;
	}
	if( $passphrase ne "" ) {
		$ssh_opts{'passphrase'} = $passphrase;
	}

	if ( $username ne "" ) {

		eval{
			$self->{_links}{'status'} = 200;
			my $sftp = Net::SFTP::Foreign->new($current_conf->{'host'}, %ssh_opts);

			unless( $sftp ){
				$self->{_links}{'status'} = "SFTP initial error";
			}

			unless( $sftp->put($upload_filename, $remote_file) ) {
				$self->{_links}{'status'} = "Error: " . $sftp->error;
			}

			$self->{_links}{'direct_link'} = $link;

			print "\n\n!!! ShutterSftpUI no GUI status !!!\n";
			print     "!!! ------------------------------------ !!!\n\n";
			print $self->{_no_gui_status};
			print   "\n!!! ------------------------------------ !!!\n\n";
			$no_gui = $self->{_no_gui_status} || FALSE;
		};

		if($@){
			$self->{_links}{'status'} = $@;
		}
	}
}
 
sub upload {
	my ( $self, $upload_filename, $username, $password ) = @_;

	eval {
		$self->unsafe_upload($upload_filename, $username, $password);
		1;
	} or do {
		my $eval_error= $@ || "Undefined error";

		print "\n\n!!! ShutterSftpUI plugin uploading error !!!\n";
		print     "!!! ------------------------------------ !!!\n\n";
		print $eval_error;
		print   "\n!!! ------------------------------------ !!!\n\n";

		my $error_dialog = Shutter::App::SimpleDialogs->new;
		$error_dialog->dlg_info_message(
			$d->get($eval_error),
			$d->get("SFTP plugin uploading error"),
			undef,
			'gtk-apply',
			undef,
			undef,
			undef,
			undef,
			undef,
			undef,
			undef,
			undef,
		);
	};

	return%{ $self->{_links} };
}

1;
