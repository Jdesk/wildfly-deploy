=head
# ##################################
# 
# Module : Wildfly.pm
#
# SYNOPSIS
# This script to deploy the EAR to Wildfly.
#
# Copyright 2015 eGovernments Foundation
#
#  Log
#  By          	Date        	Change
#  Vasanth KG  	29/11/2015	    Initial Version
#
# #######################################
=cut

# Package name
package Wildfly;

use strict;
use FindBin;
use Data::Dumper;

sub deployEar
{
	my ( $logger,$DEPLOY_RUNTIME,$EAR_ARTIFACT_NAME,$WILDFLY_HOME,$WILDFLY_URL,$WILDFLY_MGMT_PORT,$WILDFLY_USERNAME,$WILDFLY_PASSWORD, $snapshot_details,$masterHostname,$slaveHostname,$environment,$buildnumber ) = @_;
	my @slave_list;
	# Get the local system's IP address that is "en route" to "the internet":
	my $hostAddress      = Net::Address::IP::Local->public;
	$hostAddress =~ s/\n//g;
	chomp $hostAddress;
	if ( $masterHostname eq $hostAddress )
	{
		$logger->info("Deplying to master node ==> ".$masterHostname);
		my ( $status, $logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$API_SCM_HASH,$API_SCM_BRANCH,$api_artifilename,$api_arti_version,$environment,$api_git_url,$buildnumber ) = publish($logger,$DEPLOY_RUNTIME,$EAR_ARTIFACT_NAME,$WILDFLY_HOME,$WILDFLY_URL,$WILDFLY_MGMT_PORT,$WILDFLY_USERNAME,$WILDFLY_PASSWORD, $snapshot_details,$masterHostname,$environment,$buildnumber);
		if ( $status eq "success" )
		{
			$logger->info("Deployment was successful on Master Node ( ".$masterHostname." )");
			
			@slave_list = split /,/ , $slaveHostname;
			if ( scalar @slave_list )
			{
				foreach my $slave (@slave_list)
				{
					$logger->info("Deplying to slave node ==> ".$slave);
					my ( $status_slave ) = publish($logger,$DEPLOY_RUNTIME,$EAR_ARTIFACT_NAME,$WILDFLY_HOME,$WILDFLY_URL,$WILDFLY_MGMT_PORT,$WILDFLY_USERNAME,$WILDFLY_PASSWORD, $snapshot_details,$slave,$environment,$buildnumber);
					if ( $status_slave eq "success" )
					{
						$logger->info("Deployment was successful on slave Node ( ".$slave." )");
					}
				}			
			}
		}
		#Notify successful deployment
		$logger->info("Notify the deployment successful status to team.");
		Email::notify_deployment_success( $logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$API_SCM_HASH,$API_SCM_BRANCH,$api_artifilename,$api_arti_version,$environment,$api_git_url,$buildnumber ); 
	}
}

sub publish
{
	my ( $logger,$DEPLOY_RUNTIME,$api_artifilename,$WILDFLY_HOME,$WILDFLY_URL,$WILDFLY_MGMT_PORT,$WILDFLY_USERNAME,$WILDFLY_PASSWORD, $snapshot_details,$hostname,$environment,$buildnumber ) = @_;
	$logger->info(" ========== EAR Publish ===========");
	sleep 1;
	#$api_artifilename = "Calendar.war";
	# Undeploy existing ear
		$logger->info("Undeploying old EAR on ".$hostname);
		print "\n";
		my $undeploy_status = `curl -S -H "content-Type: application/json" -d '{"operation":"undeploy", "address":[{"deployment":"$api_artifilename"}]}' --digest http://$WILDFLY_USERNAME:$WILDFLY_PASSWORD\@${hostname}:$WILDFLY_MGMT_PORT/management`;
		print "\n";
		my $undeploy_json = deploy::decode_json($undeploy_status);
		( $undeploy_json->{outcome} eq "success" ) ? $logger->info("Undeployed old '".$api_artifilename."' successfully") :
		$logger->warn("Failed to undeploy the EAR '".$api_artifilename."'");
		sleep 1;
	# Remove old ear
		$logger->info("Removing old EAR on ".$hostname);
		print "\n";
		my $remove_status = `curl -S -H "content-Type: application/json" -d '{"operation":"remove", "address":[{"deployment":"$api_artifilename"}]}' --digest http://$WILDFLY_USERNAME:$WILDFLY_PASSWORD\@${hostname}:$WILDFLY_MGMT_PORT/management`;
		print "\n";
		my $remove_json = deploy::decode_json($remove_status);
		( $remove_json->{outcome} eq "success" ) ? $logger->info("Removed the old '".$api_artifilename."' successfully") :
		($logger->warn("Failed to remove the EAR '".$api_artifilename."'") && 
		$logger->warn($remove_json->{'failure-description'}));
		sleep 1;
	# Upload new EAR
		$logger->info("Uploading new EAR on ".$hostname);
		print "\n";
		my $upload_status = `curl -F "file=\@${DEPLOY_RUNTIME}/${api_artifilename}" --digest http://$WILDFLY_USERNAME:$WILDFLY_PASSWORD\@${hostname}:$WILDFLY_MGMT_PORT/management/add-content --max-time 600`;
	    print "\n";
	    my $upload_json = deploy::decode_json($upload_status);
	    ( $upload_json->{outcome} eq "success" ) ? $logger->info("New EAR '".$api_artifilename."' has been uploaded successfully") :
		($logger->error("Failed to upload the new EAR '".$api_artifilename."'")
		&& $logger->error($remove_json->{'failure-description'}) && exit 1);
		sleep 1;
	# Deploy new EAR
		$logger->info("Deploying new EAR '".$api_artifilename." on ".$hostname);
		print "\n";
		my $deploy_status = `curl -S -H "Content-Type: application/json" -d '{"content":[{"hash": {"BYTES_VALUE" : "$upload_json->{result}->{BYTES_VALUE}"}}], "address": [{"deployment":"${api_artifilename}"}], "operation":"add", "enabled":"true"}' --digest http://$WILDFLY_USERNAME:$WILDFLY_PASSWORD\@${hostname}:$WILDFLY_MGMT_PORT/management  --max-time 600`;
		print "\n";
		my $deploy_json = deploy::decode_json($deploy_status);
		#print Dumper ($deploy_json);
		if ( $deploy_json->{outcome} eq "success")
		{
			
			my ($environment,$TENANT_NAME,$par_template_dir,$baseConfigFile,$API_SCM_HASH,$API_SCM_BRANCH,$api_artifilename,$api_arti_version,$api_git_url) = (split /::/, $snapshot_details);
			return ($deploy_json->{outcome},$logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$API_SCM_HASH,$API_SCM_BRANCH,$api_artifilename,$api_arti_version,$environment,$api_git_url,$buildnumber); 
		}
		else
		{
			$logger->error("Deployment failed on Master Node ( ".$hostname." )");
			open(my $fh, '>', 'deploy_failure.log');
				print $fh Dumper $deploy_json->{'failure-description'};
			close $fh;
			my ($environment,$TENANT_NAME,$par_template_dir,$baseConfigFile,$API_SCM_HASH,$API_SCM_BRANCH,$api_artifilename,$api_arti_version,$api_git_url) = (split /::/, $snapshot_details);
			$logger->info("Notify the deployment failure to team.");
			Email::notify_deployment_failure($logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$environment,"Error log attached with this mail.",$buildnumber,$hostname,'deploy_failure.log');
			exit 1;
		}
}
sub backupEar
{
	my ( $logger ) = @_;
	$logger->info("Archiving existing EAR to backup folder.");
}

sub earPackage
{
	my ( $logger,$DEPLOY_RUNTIME_TEMP,$api_artifilename,$nexus_ds_filename ) = @_;
	$logger->info("Packing the Digital Signature to EAR.");
	system("unzip -o ".$api_artifilename." -d ".$DEPLOY_RUNTIME_TEMP."/EAR") == 0 or $logger->error("Unable to extract ".$api_artifilename) && exit 1;
	system("unzip -o ".$nexus_ds_filename." -d ".$DEPLOY_RUNTIME_TEMP."/DS") == 0 or $logger->error("Unable to extract ".$nexus_ds_filename) && exit 1;
	### New WAR Archive
	my $digi_war_filename = `ls $DEPLOY_RUNTIME_TEMP/EAR/ap-digisignweb-*`;
	chomp $digi_war_filename;
	
	$logger->warn($digi_war_filename." ==> ".$DEPLOY_RUNTIME_TEMP."/APWAR");
	system("unzip -o ".$digi_war_filename." -d ".$DEPLOY_RUNTIME_TEMP."/APWAR") == 0 or $logger->error("Unable to extract ".$digi_war_filename) && exit 1;
	### Copy LIB contect to WEB-INF/lib
	$logger->warn("Copying lib folder to Digi-sign war under WEB-INF/lib");
	system("cp -rp ".$DEPLOY_RUNTIME_TEMP."/DS/lib/* ".$DEPLOY_RUNTIME_TEMP."/APWAR/WEB-INF/lib/.") == 0 or $logger->error("Cannot copy the Digi sign libs jar to ".$DEPLOY_RUNTIME_TEMP."/APWAR/WEB-INF/lib") && exit 1;
	
	$logger->warn("Copying Resources folder to Digi-sign war");
	system("cp -rp ".$DEPLOY_RUNTIME_TEMP."/DS/resources/* ".$DEPLOY_RUNTIME_TEMP."/APWAR/resources/.") == 0 or $logger->error("Cannot copy the Digi sign resources folder to ".$DEPLOY_RUNTIME_TEMP."/APWAR/resources") && exit 1;
	
	$logger->warn("Creating NEW WAR archive");
	my $digi_war_file = (split(/\//, $digi_war_filename))[-1];
	chdir($DEPLOY_RUNTIME_TEMP."/APWAR/");
	system("jar -cvf ".$digi_war_filename." *") == 0 or $logger->error("Unable to create new digisign war archive ==> ".$digi_war_file) && exit 1;;
	#system("cp -rp ".$digi_war_filename." ".$DEPLOY_RUNTIME_TEMP."/EAR");
	### END (New WAR Archive)
	$logger->warn("Creating NEW EAR archive");
	chdir($DEPLOY_RUNTIME_TEMP."/EAR");
	system("jar -cvf ".$DEPLOY_RUNTIME_TEMP."/".$api_artifilename." *")== 0 or $logger->error("Unable to create new EAR archive ==> ".$api_artifilename) && exit 1;;
	
	$logger->warn("Replacing the EAR with Digi Sign Packaged...");
	system("cp -rp ".$DEPLOY_RUNTIME_TEMP."/".$api_artifilename." ".$DEPLOY_RUNTIME_TEMP."/../.");
}

1;