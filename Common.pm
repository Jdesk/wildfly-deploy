=head
# ##################################
# 
# Module : Setup.pm
#
# SYNOPSIS
# Common script (Jenkins Auth, Download Artifact).
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
package Common;

use strict;
use FindBin;

sub get_log_filename
{
	my $LOG_DATE = `date +%d%h%y_%H%M`;
	chomp($LOG_DATE);
	return 'deployment_'.$LOG_DATE.'.log';	
}

sub jenkinsAuthToken
{
	my ( $logger, $TENANT_NAME, $par_template_dir, $baseConfigFile, $environment, $jenkinsUserName, $jenkinsToken, $JENKINS_JOB_URL, $buildnumber) = @_;
	my $uagent = LWP::UserAgent->new;
	$logger->info("CI Authentication requested ...");
	my $req = HTTP::Request->new( GET => $JENKINS_JOB_URL."/".$buildnumber."/api/json?pretty=true" );
	$req->header('content-type' => 'application/json');
	$req->authorization_basic($jenkinsUserName, $jenkinsToken);
	$uagent->ssl_opts( verify_hostname => 0 );
	my $response = $uagent->request($req);
	($response->is_success) ? $logger->info('CI token authenticated successfully.') : ( $logger->error( "HTTP GET error code ". $response->code. " - ". $response->message."\n")
	&& Email::notify_deployment_failure($logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$environment,"Jenkins auth failure : ". $response->code. " - ". $response->message,$buildnumber) && exit 1);
	return $response->decoded_content
}

sub downloadJenkinsArtifact
{
	my ( $logger,$DEPLOY_RUNTIME, $JENKINS_JOB_URL,$buildnumber,$api_artiRelativePath,$api_artifilename,
		 $jenkinsUserName,$jenkinsToken,$sharedFolderPath,$masterHostname) = @_;
	
	# Get the local system's IP address that is "en route" to "the internet":
	my $hostAddress      = Net::Address::IP::Local->public;
	$hostAddress =~ s/\n//g;
	chomp $hostAddress;
	if ( $masterHostname eq $hostAddress )
	{
		$logger->info("Downloading the EAR Artifact from CI to Master Node ==> ".$masterHostname);
		if ( not -w $DEPLOY_RUNTIME ) 
		{
	        $logger->fatal("Directory '".$DEPLOY_RUNTIME."' is not writable...Permission denied.");
	        exit 1;
	    }
		my $uagent = LWP::UserAgent->new;
		$uagent->timeout(300);
		my $req = HTTP::Request->new( GET => $JENKINS_JOB_URL."/".$buildnumber."/artifact/".$api_artiRelativePath );
		$req->authorization_basic($jenkinsUserName, $jenkinsToken);
		$uagent->ssl_opts( verify_hostname => 0 );
		my $response = $uagent->request($req,$DEPLOY_RUNTIME."/".$api_artifilename);
		if ($response->is_success)
		{
			$logger->info($api_artifilename." downloaded to RUNTIME folder ==> ".$DEPLOY_RUNTIME);
			if ( ! system("mv ".$DEPLOY_RUNTIME."/".$api_artifilename." ".$DEPLOY_RUNTIME."/egov-ear.ear") )
			{
				$logger->info("EAR has been renamed to $DEPLOY_RUNTIME/egov-ear.ear");
			}
			else
			{
				$logger->error("Unable to rename the EAR.");
				exit 1;
			}
			return ("egov-ear.ear");
		}
		else 
		{
			$logger->error("Unable to download the ".$api_artifilename." file : ".$response->message);
			exit 1;	
		}
	}
	else
	{
		$logger->warn("EAR download skipping on '".$hostAddress."' as ear pull only happens in Master ==> ".$masterHostname);
	}
}

sub copyArtifact
{
	my ( $logger,$DEPLOY_RUNTIME,$sharedFolderPath,$api_artifilename ) = @_;
	if ( ! system("cp -rp ".$sharedFolderPath."/".$api_artifilename." ".$DEPLOY_RUNTIME."/egov-ear.ear") )
	{
		$logger->info("EAR has been copied from NFS to $DEPLOY_RUNTIME");
	}
	else
	{
		$logger->fatal("Unable to copy the EAR to $DEPLOY_RUNTIME");
		exit 1;
	}
	return ("egov-ear.ear");
}

sub validateJenkinsVariable
{
	my ( $logger, $jenkinsUserName , $jenkinsToken, $error_flag) = @_;
	if ( ! defined $jenkinsUserName)
	{
		$logger->error("Please export the JENKINS_USERNAME as environment variable.");
		$error_flag=$error_flag+1;
	}
	if ( ! defined $jenkinsToken)
	{
		$logger->error("Please export the JENKINS_AUTH_URL_TOKEN as environment variable.");
		$error_flag=$error_flag+1;
	}
	if ( $error_flag > 0 )
	{
		exit 1;
	}
}

sub usage
{
	my ( $logger, $environment, $buildnumber, $baseConfigFile ) = @_;
	if ( ! defined $environment || ! defined $buildnumber )
	{
		$logger->error("Invalid Options...!\n\n  Usage: $0 -e <qa/uat/prod> -b <build-number>\n  Options:
		-e, --environment	Specify environment <qa/uat/prod>.
		-b, --buildnumber	Specify the build number og environment specific Job.
		-c, --config (Optional)	Specify the configuration file name..\n\n  Ensure that the JENKINS_USERNAME and JENKINS_PASSWORD are exported as environment variable.
		\n");
		exit 1;
	}
}

sub parseConfigFile
{
	my ( $DEPLOY_HOME, $baseConfProperties, $environment, $logger ) = @_;
	$logger->info("Loading '$environment' configuration properties.");
	
	my $TENANT_NAME = $baseConfProperties->getProperty("tenant.name");
#    if ( $TENANT_NAME eq "" ) 
#    {
#	      $logger->error("TENANT name must require, should not be empty.");
#	      exit 1;
#    }
	
	my $WILDFLY_HOME = $baseConfProperties->getProperty($environment.".wildfly.home");
    if ( $WILDFLY_HOME eq "" || ! -d $WILDFLY_HOME ) 
    {
	      $logger->error("Wildfly home is not valid path.");
	      exit 1;
    }
    
    my $WILDFLY_URL = $baseConfProperties->getProperty($environment.".wildfly.url");
    if ( $WILDFLY_URL eq "" ) 
    {
	      $logger->error("Wildfly url should not be empty");
	      exit 1;
    }

    my $JENKINS_URL = $baseConfProperties->getProperty($environment.".jenkins.url");
    if ( $JENKINS_URL eq "" ) 
    {
	      $logger->error("Jenkins CI url should not be empty.");
	      exit 1;
    }
    
    my $masterHostname = $baseConfProperties->getProperty($environment.".master.hostaddr");
    if ( $masterHostname eq "" ) 
    {
	      $logger->error("Host IP must require to identify the master server...!");
	      exit 1;
    }
    
    my $slaveHostname = $baseConfProperties->getProperty($environment.".slaves.hostaddr");
    
    my $sharedFolderPath = $baseConfProperties->getProperty($environment.".earsharedfolder.path");

    my $wildfly_context = $baseConfProperties->getProperty($environment.".wildfly.context");
    if ( $wildfly_context eq "" ) 
    {
	      $logger->error("Wildfly context path is empty.");
	      exit 1;
    }
    
    my $WILDFLY_MGMT_PORT = $baseConfProperties->getProperty($environment.".wildfly.mgmt.port");
    if ( $WILDFLY_MGMT_PORT eq "" ) 
    {
	      $logger->error("Wildfly management port should not be empty.");
	      exit 1;
    }
    
    my $NEXUS_HOME_URL = $baseConfProperties->getProperty("nexus.url");
    if ( $NEXUS_HOME_URL eq "" ) 
    {
	      $logger->error("Nexus home url should not be empty.");
	      exit 1;
    }
    
    my $NEXUS_PUBLIC_REPO = $baseConfProperties->getProperty("nexus.public.repository");
    if ( $NEXUS_PUBLIC_REPO eq "" ) 
    {
	      $logger->error("Nexus public repository should not be empty.");
	      exit 1;
    }
    
    my $NEXUS_GROUP_ID = $baseConfProperties->getProperty("nexus.tenant.group.id");
    if ( $NEXUS_GROUP_ID eq "" ) 
    {
	      $logger->error("Nexus group id should not be empty.");
	      exit 1;
    }

    my $NEXUS_ARTIFACT_ID = $baseConfProperties->getProperty("nexus.tenant.artifact.id");
    if ( $NEXUS_GROUP_ID eq "" ) 
    {
	      $logger->error("Nexus artifact id should not be empty.");
	      exit 1;
    }
    my $NEXUS_PACKAGE_TYPE = $baseConfProperties->getProperty("nexus.package.type");
    if ( $NEXUS_PACKAGE_TYPE eq "" ) 
    {
	      $logger->error("Nexus package type should not be empty.");
	      exit 1;
    }
    
    my $NEXUS_VERSION = $baseConfProperties->getProperty(${environment}.".digisign.nexus.version.id");
    if ( $NEXUS_VERSION eq "" ) 
    {
	      $logger->error("Nexus tenant version id should not be empty.");
	      exit 1;
    }
    
    my $WILDFLY_USERNAME = $baseConfProperties->getProperty(${environment}.".wildfly.mgmt.username");
    if ( $WILDFLY_USERNAME eq "" ) 
    {
	      $logger->error("Wildfly mgmt user should not be empty.");
	      exit 1;
    }
    
    my $WILDFLY_PASSWORD = $baseConfProperties->getProperty(${environment}.".wildfly.mgmt.password");
    if ( $WILDFLY_PASSWORD eq "" ) 
    {
	      $logger->error("Wildfly mgmt user password should not be empty.");
	      exit 1;
    }
    
    my $digiSign_status = $baseConfProperties->getProperty(${environment}.".digisign.package");

    return ($TENANT_NAME,$WILDFLY_USERNAME, $WILDFLY_PASSWORD, $WILDFLY_HOME,$WILDFLY_URL,$WILDFLY_MGMT_PORT,
    $JENKINS_URL,$masterHostname,$sharedFolderPath,$wildfly_context,$NEXUS_HOME_URL,$NEXUS_PUBLIC_REPO,
    $NEXUS_GROUP_ID,$NEXUS_ARTIFACT_ID,$NEXUS_PACKAGE_TYPE,$NEXUS_VERSION,$digiSign_status,$slaveHostname);
}

1;