package PhaidraAPI::Model::Collection;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Object;

sub order {

	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $members = shift;
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };

    my $xml = "<co:collection_order xmlns:co=\"http://phaidra.univie.ac.at/XML/collection_order/V1.0\">";
	foreach my $m (@{$members}){
		$xml .= "<co:member pos=\"".$m->{'pos'}."\">".$m->{pid}."</co:member>"
	}
	$xml .= "</co:collection_order>";

	# does it already exists? we have to use modify instead of add method if it does
	my $search_model = PhaidraAPI::Model::Search->new;
	my $sr = $search_model->datastream_exists($c, $pid, 'COLLECTIONORDER');
	if($sr->{status} ne 200){
		unshift @{$res->{alerts}}, @{$sr->{alerts}};
		$res->{status} = $sr->{status};
		return $res;
	}

	if($sr->{'exists'}){

		my $object_model = PhaidraAPI::Model::Object->new;
		my $r = $object_model->modify_datastream($c, $pid, "COLLECTIONORDER", "text/xml", undef, undef, $xml, $username, $password);
	  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
	    $res->{status} = $r->{status};
	    if($r->{status} ne 200){
	    	return $res;
	    }

	}else{

		my $object_model = PhaidraAPI::Model::Object->new;
		my $r = $object_model->add_datastream($c, $pid, "COLLECTIONORDER", "text/xml", undef, undef, $xml, "X", $username, $password);
	  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
	    $res->{status} = $r->{status};
	    if($r->{status} ne 200){
	    	return $res;
	    }

	}

	return $res;
}

sub create {

	my $self = shift;
    my $c = shift;
    my $metadata = shift;
    my $members = shift;
    my $username = shift;
    my $password = shift;
    #my $cb = shift;

    my $res = { alerts => [], status => 200 };

    # create object
    my $pid;
    my $object_model = PhaidraAPI::Model::Object->new;
    my $res_create = $object_model->create($c, 'cmodel:Collection', $username, $password);
    if($res_create->{status} ne 200){
		return $res_create;
	}
	$pid = $res_create->{pid};
	    
	my $res_md = $object_model->save_metadata($c, $pid, $metadata, $username, $password);
	if($res_md->{status} ne 200){
		return $res_md;
	}

    $c->app->log->debug("Activating object");
    # activate
    my $res_act = $object_model->modify($c, $pid, 'A', undef, undef, undef, undef, $username, $password);

    $c->app->log->debug("Adding members");
    # add members
    if($members){
	    my $members_size = scalar @{$members};
	    if($members_size > 0){
		    my @relationships;
		    foreach my $member (@{$members}){
				push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasCollectionMember", object => "info:fedora/".$member->{pid} };
		    }
			my $r = $object_model->add_relationships($c, $pid, \@relationships, $username, $password);
		  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
		    $res->{status} = $r->{status};
		    if($r->{status} ne 200){
		    	return $res;
		    }
	    }

	    # order members, if any positions are defined
	    my @ordered_members;
	    foreach my $member (@{$members}){
	    	if(exists($member->{'pos'})){
	    		push @ordered_members, $member;
	    	}
		}
		my $ordered_members_size = scalar @ordered_members;
		if($ordered_members_size > 0){
			my $coll_model = PhaidraAPI::Model::Collection->new;
			my $r = $coll_model->order($c, $pid, \@ordered_members, $username, $password);
			push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
		    $res->{status} = $r->{status};
		    if($r->{status} ne 200){
		    	return $res;
		    }
		}
    }
	$res->{pid} = $pid;

	return $res;
  	#return $self->$cb($res);
}


sub get_members {

	my $self = shift;
    my $c = shift;
    my $pid = shift;

	my $res = { members => [], alerts => [], status => 200 };

	# get members
	my $search_model = PhaidraAPI::Model::Search->new;
	my $sr = $search_model->triples($c, "<info:fedora/$pid> <info:fedora/fedora-system:def/relations-external#hasCollectionMember> *");
	push @{$res->{alerts}}, $sr->{alerts} if scalar @{$sr->{alerts}} > 0;
	$res->{status} = $sr->{status};
	if($sr->{status} ne 200){
		return $res;
	}

	my %members;
	foreach my $statement (@{$sr->{result}}){
		@{$statement}[2] =~ m/^\<info:fedora\/([a-zA-Z\-]+:[0-9]+)\>$/g;
		$members{$1} = { 'pos' => undef };
	}

	# check order definition
	my $search_model = PhaidraAPI::Model::Search->new;
	my $sr = $search_model->datastream_exists($c, $pid, 'COLLECTIONORDER');
	if($sr->{status} ne 200){
		$c->app->log->error("Cannot find out if COLLECTIONORDER exists for pid: $pid and username: ".$c->stash->{basic_auth_credentials}->{username});
	}else{
		if($sr->{'exists'}){
			my $object_model = PhaidraAPI::Model::Object->new;
			my $ores = $object_model->get_datastream($c, $pid, 'COLLECTIONORDER', undef, undef, 1);
			if($ores->{status} ne 200){
				$c->app->log->error("Cannot get COLLECTIONORDER for pid: $pid and username: ".$c->stash->{basic_auth_credentials}->{username});
			}else{
				push @{$res->{alerts}}, $ores->{alerts} if scalar @{$ores->{alerts}} > 0;
				$res->{status} = $ores->{status};

				my $xml = Mojo::DOM->new($ores->{COLLECTIONORDER});
				$xml->find('member[pos]')->each(sub {
					my $m = shift;
					my $pid = $m->text;
					$members{$pid}->{'pos'} = $m->{'pos'};
				});

				my @ordered_members;
				foreach my $p (keys %members){
					push @ordered_members, { pid => $p, 'pos' =>  $members{$p}->{'pos'}};
				}

				sub undef_sort {
				  return 1 unless(defined($a->{'pos'}));
				  return -1 unless(defined($b->{'pos'}));
				  return $a->{'pos'} <=> $b->{'pos'};
				}
				@ordered_members = sort undef_sort @ordered_members;

				$res->{members} = \@ordered_members;
				return $res;
			}
		}
	}

	# return non-ordered members
	my @not_ordered_members;
	foreach my $p (keys %members){
		push @not_ordered_members, { pid => $p, 'pos' =>  undef};
	}
	$res->{members} = \@not_ordered_members;
	return $res;

}


1;
__END__
