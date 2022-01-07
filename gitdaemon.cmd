@rem SOURCE: http://freshbrewedcode.com/derekgreer/2012/02/19/hosting-a-git-repository-in-windows/

@rem Start Git Daemon Read only
git daemon --verbose --base-path=c:\workspace\Repo --export-all  %1 

@rem Write access
@rem git daemon --reuseaddr --base-path=c:\workspace\Repo --export-all --verbose --enable=receive-pack %1


@rem USAGE:
@rem Make sure your repo directory is shared, so that other people can access your folders.
@rem Replace with your computer address:
@rem git fetch git://wooe052a7.woo.us.bosch.com/.git
@rem git clone git://wooe052a7.woo.us.bosch.com/.git MyRepo

