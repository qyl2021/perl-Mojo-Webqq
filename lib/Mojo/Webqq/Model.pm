package Mojo::Webqq::Model;
use strict;
use List::Util qw(first);
use base qw(Mojo::Webqq::Model::Base);
use Mojo::Webqq::User;
use Mojo::Webqq::Friend;
use Mojo::Webqq::Group;
use Mojo::Webqq::Discuss;
use Mojo::Webqq::Discuss::Member;
use Mojo::Webqq::Group::Member;
use Mojo::Webqq::Model::Remote::_get_user_info;
use Mojo::Webqq::Model::Remote::get_single_long_nick;
use Mojo::Webqq::Model::Remote::get_qq_from_id;
use Mojo::Webqq::Model::Remote::_get_user_friends;
use Mojo::Webqq::Model::Remote::_get_user_friends_ext;
use Mojo::Webqq::Model::Remote::_get_friends_state;
use Mojo::Webqq::Model::Remote::_get_group_list_info;
use Mojo::Webqq::Model::Remote::_get_group_list_info_ext;
use Mojo::Webqq::Model::Remote::_get_group_info;
use Mojo::Webqq::Model::Remote::_get_group_info_ext;
use Mojo::Webqq::Model::Remote::_get_discuss_info;
use Mojo::Webqq::Model::Remote::_get_discuss_list_info;
use Mojo::Webqq::Model::Remote::_get_recent_info;
use Mojo::Webqq::Model::Remote::_invite_friend;
use Mojo::Webqq::Model::Remote::_set_group_admin;
use Mojo::Webqq::Model::Remote::_remove_group_admin;
use Mojo::Webqq::Model::Remote::_kick_group_member;
use Mojo::Webqq::Model::Remote::_set_group_member_card;
use Mojo::Webqq::Model::Remote::_shutup_group_member;
use Mojo::Webqq::Model::Remote::_qiandao;
use Encode ();

sub time33 {
    use integer;
    my $self = shift;
    my $t = shift;
    my $e = 0;
    my $i = 0;
    for( my $n = length($t); $i<$n; $i++ ){
        $e  = ( 33 * $e + ord(substr($t,$i,1)) ) % 4294967296;
    }
    return $e;
}
sub hash33{
    use integer;
    my $self = shift;
    my $t = shift;
    my $n = length($t);
    my $e = 0;
    for(my $i=0;$n>$i;$i++ ){
        $e += ($e << 5) + ord(substr($t,$i,1));
    }
    return 2147483647 & $e;
}
sub hash {
    my $self = shift;
    my $ptwebqq = shift;
    my $uin = shift;

    $uin .= "";
    my @ptb;
    for(my $i =0;$i<length($ptwebqq);$i++){
        $ptb[$i % 4] ^= ord(substr($ptwebqq,$i,1));
    }
    my @salt = ("EC", "OK");
    my @uinByte;
    $uinByte[0] =  $uin >> 24 & 0xFF ^ ord(substr($salt[0],0,1));
    $uinByte[1] =  $uin >> 16 & 0xFF ^ ord(substr($salt[0],1,1));
    $uinByte[2] =  $uin >> 8  & 0xFF ^ ord(substr($salt[1],0,1));
    $uinByte[3] =  $uin       & 0xFF ^ ord(substr($salt[1],1,1));
    my @result;
    for(my $i=0;$i<8;$i++){
        $result[$i] = $i%2==0?$ptb[$i>>1]:$uinByte[$i>>1]; 
    }
    my @hex = ("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F");
    my $buf = "";
    for(my $i=0;$i<@result;$i++){
        $buf .= $hex[$result[$i] >> 4 & 0xF];
        $buf .= $hex[$result[$i] & 0xF];
    }

    return $buf;
}

sub is_support_model_ext {
    my $self = shift;
    return $self->model_ext;
    #return $self->uid && $self->pwd
    #my $ret = $self->search_cookie("p_skey") && $self->search_cookie("skey");
    #$self->model_ext($ret || 0);
    #return $ret;
}
sub get_model_status{
    my $self = shift;
    if(     defined $self->model_status->{friend} 
        and defined $self->model_status->{group}
    ){
        my $is_fail =
                $self->model_status->{friend} == 0
            &&  $self->model_status->{group} == 0
        ;
        return $is_fail?0:1;
    }
    else{
        return -1;
    }
}
sub get_csrf_token {
    use integer;
    my $self = shift;
    if(not $self->is_support_model_ext){
        $self->error("????????????????????????????????????????????????CSRF Token");
        return;
    }
    return $self->csrf_token if defined $self->csrf_token;
    my $t = $self->search_cookie("skey");
    my $n = 0;
    my $o=length($t);
    my $r;
    if($t){
        for($r=5381;$o>$n;$n++){
            $r += ($r<<5) + ord(substr($t,$n,1));
        }
        my $token = 2147483647 & $r;
        $self->csrf_token($token);
        return $token;
    } 
}
sub each_friend{
    my $self = shift;
    my $callback = shift;
    $self->die("???????????????????????????") if ref $callback ne "CODE";
    $self->update_friend(is_blocking=>1,is_update_friend_ext=>1) if @{$self->friend} == 0;
    for (@{$self->friend}){
        $callback->($self,$_);   
    }
}
sub each_group{
    my $self = shift;
    my $callback = shift;
    $self->die("???????????????????????????") if ref $callback ne "CODE";
    $self->update_group(is_blocking=>1,is_update_group_member=>0) if @{$self->group} == 0;
    for (@{$self->group}){
        $callback->($self,$_);     
    }
}

sub each_discuss{
    my $self = shift;
    my $callback = shift;
    $self->die("???????????????????????????") if ref $callback ne "CODE";
    $self->update_discuss(is_blocking=>1,is_update_discuss_member=>0) if @{$self->discuss} == 0;
    for (@{$self->discuss}){
        $callback->($self,$_);
    }
}
sub each_group_member{
    my $self = shift;
    my $callback = shift;
    $self->die("???????????????????????????") if ref $callback ne "CODE";
    if(@{$self->group} == 0){
        $self->update_group(is_blocking=>1,is_update_group_member=>1);
    }
    else{
        for( @{$self->group}){
            $_->update_group_member(is_blocking=>1,) if $_->is_empty;   
        }
    }
    my @member = map {@{$_->member}} grep {ref $_->member eq "ARRAY"}  @{$self->group};
    for (@member){
        $callback->($self,$_);
    }
}
sub each_discuss_member{
    my $self = shift;
    my $callback = shift;
    $self->die("???????????????????????????") if ref $callback ne "CODE";
    if(@{$self->discuss} == 0){
        $self->update_discuss(is_blocking=>1,is_update_discuss_member=>1);
    }
    else{
        for( @{$self->discuss}){
            $_->update_discuss_member(is_blocking=>1,) if $_->is_empty;
        }
    }
    my @member = map {@{$_->member}} grep {ref $_->member eq "ARRAY"}  @{$self->discuss};
    for (@member){
        $callback->($self,$_);
    }
}

sub update_user {
    my $self = shift;
    my $is_blocking = ! shift;
    $self->info("??????????????????...\n");
    my $handle = sub{
        my $user_info = shift;
        unless ( defined $user_info ) {
            $self->warn("????????????????????????\n");
            $self->user(Mojo::Webqq::User->new({id=>$self->uid,uid=>$self->uid}));
            $self->emit("model_update"=>"user",0);
            return;
        }       
        $self->user(Mojo::Webqq::User->new($user_info));
        $self->emit("model_update"=>"user",1);
    };
    if($is_blocking){
        my $user_info = $self->_get_user_info();
        $handle->($user_info);
    } 
    else{
        $self->_get_user_info($handle);
    }
}

sub remove_friend {
    my $self = shift;
    my $friend = shift;
    $self->die("????????????????????????\n") if ref $friend ne "Mojo::Webqq::Friend";
    for(my $i=0;@{$self->friend};$i++){
        if($friend->id eq $self->friend->[$i]->id){
            splice @{$self->friend},$i,1;
            return 1; 
        }
    }
    return 0;
}
sub add_friend {
    my $self = shift;
    my $friend = shift;
    my $nocheck = shift;
    $self->die("????????????????????????\n") if ref $friend ne "Mojo::Webqq::Friend";
    if(@{$self->friend}  == 0){
        push @{$self->friend},$friend;
        return $self;
    }
    if($nocheck){
        push @{$self->friend},$friend;
        return $self;
    }
    my $f = $self->search_friend(id => $friend->id);
    if(defined $f){
        %$f = %$friend;
    }
    else{
        push @{$self->friend},$friend;
    }
    return $self;
}

sub update_friend_ext {
    my $self = shift;
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking} ;
    if ( not $self->is_support_model_ext){
        $self->warn("??????????????????????????????");
        return;
    }
    my $handle = sub{
        my $friends_ext_info = shift;
        if(defined $friends_ext_info and ref $friends_ext_info eq "ARRAY"){
            $self->info("????????????????????????...");
            my(undef,$ext)=$self->array_unique($friends_ext_info,sub{$_[0]->{displayname} . "|" . $_[0]->{category}},"friend_ext");
            my $unique_friend = $self->array_unique($self->friend,sub{$_[0]->displayname . "|" . $_[0]->category},"friend");
            for my $f(@$unique_friend){
                my $id = $f->displayname . "|" . $f->category;
                next if not exists $ext->{$id};
                $f->{uid} = $ext->{$id}{uid};
            }
            
            if($self->log_level eq 'debug'){
                for(@{$self->friend}){
                    $self->debug("????????????[" . $_->displayname . "|" . $_->category . "]????????????uid??????") if not $_->uid;
                }
            }

            $self->emit("model_update"=>"friend_ext",1);
        }
        else{
            $self->warn("??????????????????????????????");
            $self->emit("model_update"=>"friend_ext",0);
        }
    };
    if($p{is_blocking}){
        my $friends_ext_info = $self->_get_user_friends_ext();
        $handle->($friends_ext_info);
    }
    else{
        $self->_get_user_friends_ext($handle);    
    }
}
sub update_friend {
    my $self = shift;
    if(ref $_[0] eq "Mojo::Webqq::Friend"){
        my $friend = shift;
        my %p = @_;
        $p{is_blocking} = 1 if not defined $p{is_blocking};
        $self->info("???????????? [ " . $friend->displayname .  " ] ??????...");
        my $handle = sub{
            my $friend_info = shift;
            if(defined $friend_info){$friend->update($friend_info);}
            else{$self->warn("???????????? [ " . $friend->displayname .  " ] ????????????...");}
        };
        if($p{is_blocking}){
            my $friend_info = $self->_get_friend_info($friend->id);
            $handle->($friend_info);
        }
        else{
            $self->_get_friend_info($friend->id,$handle);
        }
        return $self;
    }
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    $p{is_update_friend_ext} = 1 if not defined $p{is_update_friend_ext};
    my $handle = sub{
        my @friends;
        my $friends_info = shift;
        if(defined $friends_info){
            $self->info("??????????????????..."); 
            push @friends,Mojo::Webqq::Friend->new($_) for @{$friends_info};
            if(ref $self->friend eq "ARRAY" and @{$self->friend}  == 0){
                $self->friend(\@friends);
            }
            else{
                my($new_friends,$lost_friends,$sames) = $self->array_diff($self->friend,\@friends,sub{$_[0]->id});
                for(@{$new_friends}){
                    $self->add_friend($_);
                    $self->emit(new_friend=>$_);
                }
                for(@{$lost_friends}){
                    $self->remove_friend($_);
                    $self->emit(lose_friend=>$_);
                }
                for(@{$sames}){
                    my($old,$new) = @$_;
                    $old->update($new);
                }
            }
            $self->emit("model_update","friend",1);
            $self->update_friend_ext(is_blocking=>$p{is_blocking}) if $p{is_update_friend_ext};
        }
        else{$self->warn("????????????????????????");$self->emit("model_update","friend",0);}
    };
    if($p{is_blocking}){
        my $friends_info = $self->_get_user_friends();
        $handle->($friends_info);
    }
    else{
        $self->_get_user_friends($handle);
    }
}
sub search_friend {
    no warnings 'uninitialized';
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    $self->update_friend(is_blocking=>1,is_update_friend_ext=>1) if @{ $self->friend } == 0;
    if(wantarray){
        return grep {my $f = $_;(first {$p{$_} ne $f->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->friend};
    }
    else{
        return first {my $f = $_;(first {$p{$_} ne $f->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->friend};
    }
}

sub add_group{
    my $self = shift;
    my $group = shift;
    my $nocheck = shift;
    $self->die("????????????????????????") if ref $group ne "Mojo::Webqq::Group";
    if(@{$self->group}  == 0){
        push @{$self->group},$group;
        return $self;
    }
    if($nocheck){
        push @{$self->group},$group;
        return $self;
    }
    my $g = $self->search_group(id => $group->id);
    if(defined $g){
        %$g = %$group;
    }
    else{#new group
        push @{$self->group},$group;
    }
    return $self;
}
sub remove_group{
    my $self = shift;
    my $group = shift;
    $self->die("????????????????????????") if ref $group ne "Mojo::Webqq::Group";
    for(my $i=0;@{$self->group};$i++){
        if($group->id eq $self->group->[$i]->id){
            splice @{$self->group},$i,1;
            return 1;
        }
    }
    return 0;
}
sub update_group_ext {
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("??????????????????????????????");
        return;
    }
    return if @{ $self->group } == 0;
    my $group;
    $group = shift if ref $_[0] eq "Mojo::Webqq::Group";
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    $p{is_update_group_member_ext} = 1 if not defined $p{is_update_group_member_ext};    

    if(defined $group and defined $group->uid){#????????????????????????????????????????????????
        $self->update_group_member_ext($group,%p) if $p{is_update_group_member_ext};
        return;
    }
    elsif( (!defined $group) and (! first { !defined $_->uid} @{$self->group} ) ){ #????????????????????????????????????
        for(@{$self->group}){
            $self->update_group_member_ext($_,%p) if $p{is_update_group_member_ext};
        }  
        return;
    }
    my $handle = sub{
        my $group_list_ext = shift;
        if(defined $group_list_ext and ref $group_list_ext eq "ARRAY"){
            $self->info("???????????????????????????...");
            my(undef,$gext)= $self->array_unique($group_list_ext,sub{$_[0]->{name}},"group_ext");
            my $unique_group = $self->array_unique($self->group,sub{$_[0]->name},"group"); 
            my @groups = defined $group?(grep {$_->id eq $group->id} @$unique_group) : @$unique_group;
            if($p{is_blocking}){
                for my $g (@groups){
                    my $id = $g->name;
                    next if not exists $gext->{$id};
                    $g->update($gext->{$id});
                    $self->update_group_member_ext($g,%p) if $p{is_update_group_member_ext};
                }
            }
            else{
                my $i = -3;
                for my $g (@groups){
                    my $id = $g->name;
                    next if not exists $gext->{$id};
                    $g->update($gext->{$id});
                    $self->timer($i+3,sub{
                        $self->update_group_member_ext($g,%p) if $p{is_update_group_member_ext};
                    });
                    $i++;
                }
            }
            $self->emit("model_update","group_ext",1);
        }
        else{$self->warn("???????????????????????????");$self->emit("model_update","group_ext",0);}
    };
    if($p{is_blocking}){
        my $group_list_ext = $self->_get_group_list_info_ext();
        $handle->($group_list_ext);   
    }
    else{
        $self->_get_group_list_info_ext($handle);
    }
}
sub update_group_member_ext {
    my $self = shift;
    my $group = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("??????[ ". $group->name . " ]????????????????????????????????????");
        return;
    }
    $self->die("????????????????????????") if ref $group ne "Mojo::Webqq::Group";
    if(not defined $group->uid){
        $self->warn("??????[ ". $group->name . " ]??????????????????uid????????????????????????????????????");
        return;
    }
    if($group->is_empty){
        $self->warn("??????[ ". $group->name . " ]??????????????????????????????????????????????????????");
        return;
    }
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    my $handle = sub{
        my $group_info_ext = shift;
        if(defined $group_info_ext){
            $self->info("????????????[ ". $group->name . " ]??????????????????");
            my $unique_sub = sub{
                my $name = $_[0]->{name} // "";
                my $card = $_[0]->{card} // "";
                if(ref $self->group_member_identify_callback eq 'CODE'){
                    return $self->group_member_identify_callback->($name,$card);
                }
                else{
                    return $self->group_member_card_ext_only? $name: $name . $card;
                }
            };
            my(undef,$mext) = $self->array_unique($group_info_ext->{member},$unique_sub,$group->name . " member_ext");
            my $unique_member = $self->array_unique($group->member,$unique_sub,$group->name . " member");
            for(@$unique_member){
                my $id = $unique_sub->($_);
                next if not exists $mext->{$id};
                $_->update($mext->{$id});
            }
            if($self->log_level eq 'debug'){
                for(@{$group->member}){
                    $self->debug("???????????????[".$_->name . "|" . $group->name ."]????????????uid??????") if not  $_->uid;
                }
            }
            $group->{max_member} //= $group_info_ext->{max_member};
            $group->{max_admin} //= $group_info_ext->{max_admin};
            $group->{_is_hold_member_ext} = 1;
            $self->emit("model_update","group_member_ext",1);
        }
        else{$self->warn("????????????[ " . $group->name . " ]????????????????????????");}
    }; 
    if($p{is_blocking}){
        my $group_info_ext = $self->_get_group_info_ext($group->uid);
        $handle->($group_info_ext);
    }
    else{
        $self->_get_group_info_ext($group->uid,$handle);
    }
    
}
sub update_group_member {
    my $self = shift;
    my $group = shift;
    $self->die("????????????????????????") if ref $group ne "Mojo::Webqq::Group";
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    $p{is_update_group_member_ext} = 1 if not defined $p{is_update_group_member_ext};
    my $handle = sub{
        my $group_info = shift;
        if(defined $group_info){ 
            $self->info("????????????[ ". $group->name . " ]????????????");
            if(ref $group_info->{member} eq 'ARRAY'){
                $group->update($group_info); 
                $self->update_group_member_ext($group,%p) if $p{is_update_group_member_ext};
            }
            else{$self->debug("????????????[ " . $group->name . " ]??????????????????")}
        }
        else{$self->warn("????????????[ " . $group->name . " ]??????????????????")}
        
    };
    if($p{is_blocking}){
        my $group_info = $self->_get_group_info($group->code);
        $handle->($group_info);
    }
    else{
        $self->_get_group_info($group->code,$handle);
    }
}
sub update_group {
    my $self = shift;
    if(ref $_[0] eq "Mojo::Webqq::Group"){
        my $group = shift;
        my %p = @_;
        $p{is_blocking} = 1 if not defined $p{is_blocking};
        $p{is_update_group_member} = 1 if not defined $p{is_update_group_member} ;
        $p{is_update_group_ext} = $p{is_blocking} if not defined $p{is_update_group_ext} ;
        $p{is_update_group_member_ext} = $p{is_update_group_ext} && $p{is_blocking}  if not defined $p{is_update_group_member_ext} ;
        my $handle = sub{
            my $group_info = shift;
            if(defined $group_info){
                if(ref $group_info->{member} eq 'ARRAY'){
                    $self->info("????????????[ ". $group->name . " ]??????");
                    $group->update($group_info);
                    $self->update_group_ext($group,%p) if $p{is_update_group_ext};
                }
                else{$self->debug("????????????[ " . $group->name . " ]??????????????????")}
            }
            else{$self->warn("????????????[ " . $group->name . " ]??????????????????")}

        };
        if($p{is_blocking}){
            my $group_info = $self->_get_group_info($group->code);
            $handle->($group_info);
        }
        else{
            $self->_get_group_info($group->code,$handle);
        }
        return $self;
    }
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking} ;
    $p{is_update_group_member} = 1 if not defined $p{is_update_group_member} ;
    $p{is_update_group_ext} = $p{is_blocking} if not defined $p{is_update_group_ext} ;
    $p{is_update_group_member_ext} = $p{is_blocking} && $p{is_update_group_ext} && $p{is_update_group_member} if not defined $p{is_update_group_member_ext} ;
    my $handle = sub{
        my @groups;
        my $group_list = shift; 
        unless(defined $group_list){
            $self->warn("???????????????????????????\n");
            $self->emit("model_update","group",0);
            return $self;
        }
        $self->info("?????????????????????...");
        for my $g (@{$group_list}){
            push @groups, Mojo::Webqq::Group->new($g);
        } 
        if(ref $self->group eq "ARRAY" and @{$self->group} == 0){
            $self->group(\@groups);
        }
        else{
            my($new_groups,$lost_groups,$sames) = $self->array_diff($self->group,\@groups,sub{$_[0]->id});  
            for(@{$new_groups}){
                $self->add_group($_);
                $self->emit(new_group=>$_) ;
            }
            for(@{$lost_groups}){
                $self->remove_group($_);
                $self->emit(lose_group=>$_) ;
            }
            for(@{$sames}){
                my($old_group,$new_group) = ($_->[0],$_->[1]);
                $old_group->update($new_group); 
            }
        }
        $self->emit("model_update","group",1);
        if($p{is_update_group_member}){
            if($p{is_blocking}){
                for(@{ $self->group }){
                    $self->update_group_member($_,%p);
                }
            }
            else{
                my $i = -3;
                for my $g (@{ $self->group }){
                    $self->timer($i+3,sub{$self->update_group_member($g,%p)});
                    $i++;
                }
            }
        }
        if($p{is_update_group_ext}){
            $self->update_group_ext(%p);
        }
    };

    if($p{is_blocking}){
        my $group_list = $self->_get_group_list_info(); 
        $handle->($group_list);
    }
    else{
        $self->_get_group_list_info($handle);
    }
}

sub search_group {
    no warnings 'uninitialized';
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    $self->update_group(is_update_group_member=>0) if @{ $self->group } == 0;
    delete $p{member};
    if(wantarray){
        return grep {my $g = $_;(first {$p{$_} ne $g->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->group};
    }
    else{
        return first {my $g = $_;(first {$p{$_} ne $g->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->group};
    }
}

sub search_group_member {
    no warnings 'uninitialized';
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    if(@{$self->group} == 0){
        $self->update_group(is_blocking=>1,is_update_group_member=>1);
    }
    else{
        for( @{$self->group}){
            $_->update_group_member(is_blocking=>1,) if $_->is_empty;
        }
    }
    my @member = map {@{$_->member}} grep {ref $_->member eq "ARRAY"}  @{$self->group};
    if(wantarray){
        return grep {my $m = $_;(first {$p{$_} ne $m->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @member;
    }
    else{
        return first {my $m = $_;(first {$p{$_} ne $m->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @member;
    }
}

sub add_discuss {
    my $self = shift;
    my $discuss = shift;
    my $nocheck = shift;
    $self->die("????????????????????????") if ref $discuss ne "Mojo::Webqq::Discuss";
    if(@{$self->discuss}  == 0){
        push @{$self->discuss},$discuss;
        return $self;
    }
    if($nocheck){
        push @{$self->discuss},$discuss;
        return $self;
    }
    my $d = $self->search_discuss(id => $discuss->id);
    if(defined $d){
        %$d = %$discuss;
    }
    else{#new discuss
        push @{$self->discuss},$discuss;
    }
    return $self;

}
sub remove_discuss {
    my $self = shift;
    my $discuss = shift;
    $self->die("????????????????????????") if ref $discuss ne "Mojo::Webqq::Discuss";
    for(my $i=0;@{$self->discuss};$i++){
        if($discuss->id eq $self->discuss->[$i]->id){
            splice @{$self->discuss},$i,1;
            return 1;
        }
    }
    return 0;
}

sub add_discuss_member {}

sub update_discuss_member{
    my $self = shift;
    my $discuss = shift; 
    $self->die("????????????????????????") if ref $discuss ne "Mojo::Webqq::Discuss";
    $self->info("???????????????[ ". $discuss->name . " ]????????????");
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    my $handle = sub{
        my $discuss_info = shift;
        if(defined $discuss_info){
            if(ref $discuss_info->{member} eq 'ARRAY'){
                $discuss->update($discuss_info);
            }
            else{$self->debug("???????????????[ " . $discuss->name . " ]??????????????????")}
        }
        else{$self->warn("???????????????[ " . $discuss->name . " ]??????????????????")}
    };

    if($p{is_blocking}){
        my $discuss_info = $self->_get_discuss_info($discuss->id);
        $handle->($discuss_info);
    }
    else{
        $self->_get_discuss_info($discuss->id,$handle);
    }
    
}
sub update_discuss {
    my $self = shift;
    if(ref $_[0] eq "Mojo::Webqq::Discuss"){
        my $discuss = shift;
        my %p = @_;
        $self->info("???????????????[ ". $discuss->name . " ]??????");
        $p{is_blocking} = 1 if not defined $p{is_blocking};
        my $handle = sub{
            my $discuss_info = shift;
            if(defined $discuss_info){
                if(ref $discuss_info->{member} eq 'ARRAY'){
                    $discuss->update($discuss_info);
                }
                else{$self->debug("???????????????[ " . $discuss->name . " ]??????????????????")}
            }
            else{$self->warn("???????????????[ " . $discuss->name . " ]??????????????????")}

        };
        if($p{is_blocking}){
            my $discuss_info = $self->_get_discuss_info($discuss->id);
            $handle->($discuss_info);
        }
        else{
            $self->_get_discuss_info($discuss->id,$handle);
        }
        return $self;
    }
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking} ;
    $p{is_update_discuss_member} = 1 if not defined $p{is_update_discuss_member} ;
    $self->info("???????????????????????????...");
    my $handle = sub{
        my @discusss;
        my $discuss_list = shift;
        unless(defined $discuss_list){
            $self->warn("??????????????????????????????\n");
            $self->emit("model_update","discuss",0);
            return $self;
        }
        for my $d (@{$discuss_list}){
            push @discusss, Mojo::Webqq::Discuss->new($d);
        }
        if(ref $self->discuss eq "ARRAY" and @{$self->discuss} == 0){
            $self->discuss(\@discusss);
        }
        else{
            my($new_discusss,$lost_discusss,$sames) = $self->array_diff($self->discuss,\@discusss,sub{$_[0]->did});
            for(@{$new_discusss}){
                $self->add_discuss($_);
                $self->emit(new_discuss=>$_) ;
            }
            for(@{$lost_discusss}){
                $self->remove_discuss($_);
                $self->emit(lose_discuss=>$_) ;
            }
            for(@{$sames}){
                my($old_discuss,$new_discuss) = ($_->[0],$_->[1]);
                $old_discuss->update($new_discuss);
            }
        }
        $self->emit("model_update","discuss",1);
        if($p{is_update_discuss_member}){
            for(@{ $self->discuss }){
                $self->update_discuss_member($_,%p);
            }
        }
    };
    if($p{is_blocking}){
        my $discuss_list = $self->_get_discuss_list_info();
        $handle->($discuss_list);
    }
    else{
        $self->_get_discuss_list_info($handle);
    }
}

sub search_discuss {
    no warnings 'uninitialized';
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    $self->update_discuss(is_blocking=>1,is_update_discuss_member=>0) if @{$self->discuss} == 0;
    delete $p{member};
    if(wantarray){
        return grep {my $d = $_;(first {$p{$_} ne $d->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->discuss};
    }
    else{
        return first {my $d = $_;(first {$p{$_} ne $d->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->discuss};
    }
}

sub search_discuss_member {
    no warnings 'uninitialized';
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    if(@{$self->discuss} == 0){
        $self->update_discuss(is_blocking=>1,is_update_discuss_member=>1);
    }
    else{
        for( @{$self->discuss}){
            $_->update_discuss_member(is_blocking=>1,) if $_->is_empty;
        }
    }
    my @member = map {@{$_->member}} grep {ref $_->member eq "ARRAY"}  @{$self->discuss};
    if(wantarray){
        return grep {my $m = $_;(first {$p{$_} ne $m->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @member;
    }
    else{
        return first {my $m = $_;(first {$p{$_} ne $m->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @member;
    }
}

sub invite_friend{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("??????????????????????????????");
        return;
    }
    my $group = shift;
    my @friends = @_;
    if(not defined $group->uid){
        $self->error("????????????????????????????????????????????????");
        return;
    }
    if($group->role ne "manage" and $group->role ne "create"){
        $self->error("????????????????????????????????????????????????");
        return;
    }
    for(@friends){
        $self->die("???????????????") if not $_->is_friend;
    }
    my $ret = $self->_invite_friend($group->uid,map {$_->uid}  @friends);
    if($ret){$self->info("????????????????????????")}
    else{$self->error("????????????????????????")}
    return $ret;
}
sub kick_group_member{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("??????????????????????????????");
        return;
    }
    my $group = shift;
    my @members = @_;
    if(not defined $group->uid){
        $self->error("?????????????????????????????????????????????");
        return;
    }
    if($group->role ne "manage" and $group->role ne "create"){
        $self->error("?????????????????????????????????????????????");
        return;
    }
    for(@members){                                            
        $self->die("??????????????????") if not $_->is_group_member;  
    }
    my $ret = $self->_kick_group_member($group->uid,map {$_->uid} @members);
    if($ret){
        for(@members){
            $_->group->remove_group_member($_);
            $self->emit(lose_group_member=>$_);
        }
        $self->info("?????????????????????");
    }
    else{$self->error("?????????????????????")}
    return $ret;
}

sub shutup_group_member{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("??????????????????????????????");
        return;
    }
    my $group = shift;
    my $time = shift;
    my @members = @_;
    if($time<60){
        $self->error("???????????????????????????1??????");
        return;
    }
    if(not defined $group->uid){
        $self->error("????????????????????????????????????????????????");
        return;
    }
    if($group->role ne "manage" and $group->role ne "create"){
        $self->error("????????????????????????????????????????????????");
        return;
    }
    for(@members){
        $self->die("??????????????????") if not $_->is_group_member;
        if($_->role eq "admin" or $_->role eq "owner"){
            $self->error("?????????????????????????????????????????????");
            return; 
        } 
    }
    my $ret = $self->_shutup_group_member($group->uid,$time,map {$_->uid} @members);
    if($ret){$self->info("??????????????????");}
    else{$self->error("??????????????????");}
    return $ret;
}
sub speakup_group_member{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("??????????????????????????????");
        return;
    }
    my $group = shift;
    my @members = @_;
    if(not defined $group->uid){
        $self->error("????????????????????????????????????????????????");
        return;
    }
    if($group->role ne "manage" and $group->role ne "create"){
        $self->error("????????????????????????????????????????????????");
        return;
    }
    for(@members){
        $self->die("??????????????????") if not $_->is_group_member;
        if($_->role eq "admin" or $_->role eq "owner"){
            $self->error("???????????????????????????????????????????????????");
            return; 
        } 
    }
    my $ret = $self->_shutup_group_member($group->uid,0,map {$_->uid} @members);
    if($ret){$self->info("????????????????????????");}
    else{$self->error("????????????????????????");}
    return $ret;
}
sub set_group_admin{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("??????????????????????????????");
        return;
    }
    my $group = shift;
    my @members = @_;
    if(not defined $group->uid){
        $self->error("?????????????????????????????????????????????");
        return;
    }
    if($group->role ne "create"){
        $self->error("?????????????????????????????????");
        return;
    }
    for(@members){                                            
        $self->die("??????????????????") if not $_->is_group_member;
    }
    my $ret = $self->_set_group_admin($group->uid,map {$_->uid} @members);
    if($ret){
        $_->role("admin") for(@members);
        $self->info("?????????????????????");
    }
    else{$self->error("?????????????????????")}
    return $ret;
}
sub remove_group_admin{
    my $self = shift;
    my $group = shift;
    my @members = @_;
    if(not defined $group->uid){
        $self->error("?????????????????????????????????????????????");
        return;
    }
    if($group->role ne "create"){
        $self->error("?????????????????????????????????");
        return;
    }
    for(@members){
        $self->die("??????????????????") if not $_->is_group_member;
    }
    my $ret = $self->_remove_group_admin($group->uid,map {$_->uid} @members);
    if($ret){
        $_->role("member") for(@members);
        $self->info("?????????????????????");
    }
    else{$self->error("?????????????????????")}
    return $ret;
}
sub set_group_member_card{
    my $self = shift;
    my $group = shift;
    my $member = shift;
    my $card = shift;
    if(not defined $group->uid){
        $self->error("?????????????????????????????????????????????");
        return;
    }
    if(!$member->is_me and $group->role ne "create" and $group->role ne "manage"){
        $self->error("??????????????????????????????????????????????????????");
        return;
    }
    $self->die("??????????????????") if not $member->is_group_member;
    my $ret = $self->_set_group_member_card($group->uid,$member->uid,$card);
    if($ret){
        $member->card($card);
        if(length $card){$self->info("?????????????????????");}
        else{$self->info("?????????????????????");}
    }
    else{$self->error("?????????????????????")}
    return $ret;
}

sub qiandao {
    my $self = shift;
    my $group = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("??????????????????????????????, ??????????????????");
        return;
    }
    $self->die("???????????????") if not $group->is_group;
    if(not defined $group->uid){
        $self->error("??????????????????????????????????????????");
        return;
    }
    my $ret = $self->_qiandao($group->uid);
    if($ret){
        $self->info("??????[ ". $group->displayname ." ]????????????");
    }
    else{$self->error("??????[ ". $group->displayname ." ]????????????")}
    return $ret;
}

sub friends{
    my $self = shift;
    $self->update_friend() if @{$self->friend} == 0;
    return @{$self->friend};
}
sub groups{
    my $self = shift;
    $self->update_group() if @{$self->group} == 0;
    return @{$self->group};
}
sub discusss{
    my $self = shift;
    $self->update_discuss() if @{$self->discuss} == 0;
    return @{$self->discuss};
}

1;
