{ config, k8s, ... }:

with k8s;

{
  require = [
    ./test.nix
    ../modules/mediawiki.nix
    ../modules/mariadb.nix
    ../modules/elasticsearch.nix
  ];

  kubernetes.modules.mediawiki-mariadb = {
    module = "mariadb";

    configuration = {
      rootPassword.name = "mediawiki-mariadb-root-password";
      mysql = {
        database = "mediawiki";
        user = {
          name = "mediawiki-mariadb-user";
          key = "username";
        };
        password = {
          name = "mediawiki-mariadb-user";
          key = "password";
        };
      };
    };
  };

  kubernetes.resources.secrets.mediawiki-mariadb-user.data = {
    username = toBase64 "mediawiki";
    password = toBase64 "mediawiki";
  };

  kubernetes.resources.secrets.mediawiki-mariadb-root-password.data = {
    password = toBase64 "mediawiki";
  };

  kubernetes.modules.mediawiki-elasticsearch = {
    module = "elasticsearch";

    configuration = {
      name = "mediawiki-cluster";
      image = "quay.io/pires/docker-elasticsearch-kubernetes:5.6.4";
      nodeSets.nodes = {
        roles = ["master" "client" "data"];
        replicas = 1;
        storage = {
          enable = true;
          size = "10G";
        };
      };
    };
  };

  kubernetes.resources.secrets.mediawiki-admin.data.password = toBase64 "password";

  kubernetes.modules.mediawiki = {
    module = "mediawiki";

    configuration = {
      adminPassword.name = "mediawiki-admin";
      url = "http://mediawiki.default.svc.cluster.local/";
      db.host = "mediawiki-mariadb";
      db.username.name = "mediawiki-mariadb-user";
      db.password.name = "mediawiki-mariadb-user";
      customConfig = ''
        $wgEnableUploads = true;

        // Network authentication
        require_once "$IP/extensions/NetworkAuth/NetworkAuth.php";

        // VisualEditor
        wfLoadExtension('VisualEditor');
        $wgDefaultUserOptions['visualeditor-enable'] = 1; // Enable by default for everybody
        $wgVirtualRestConfig['modules']['parsoid'] = array(
          'url' => 'http://127.0.0.1:8000',
          'domain' => 'localhost',
          'prefix' => 'localhost'
        );
        $wgNetworkAuthUsers[] = array(
          'iprange' => array('127.0.0.1/32'),
          'user' => 'parsoid'
        );
        $wgVirtualRestConfig['modules']['parsoid']['forwardCookies'] = true;
        $wgSessionsInObjectCache = true;

        // Wikidata
        $wgEnableWikibaseRepo = true;
        $wgEnableWikibaseClient = true;
        $wmgUseWikibaseRepo = true;
        require_once "$IP/extensions/Wikibase/repo/Wikibase.php";
        require_once "$IP/extensions/Wikibase/repo/ExampleSettings.php";
        //require_once "$IP/extensions/WikibaseImport/WikibaseImport.php";
        $wgWBRepoSettings['formatterUrlProperty'] = 'P2';

        // Scribunto
        wfLoadExtension('Scribunto');
        $wgScribuntoDefaultEngine = 'luastandalone';
        $wgScribuntoUseGeSHi = true;
        $wgScribuntoUseCodeEditor = true;

        // Code editor
        wfLoadExtension('CodeEditor');

        // SyntaxHighlight
        wfLoadExtension('SyntaxHighlight_GeSHi');

        // Wiki editor
        wfLoadExtension( 'WikiEditor'  );
        $wgDefaultUserOptions['usebetatoolbar'] = 1;
        $wgDefaultUserOptions['usebetatoolbar-cgd'] = 1;
        $wgDefaultUserOptions['wikieditor-preview'] = 1;

        // Parser functions
        wfLoadExtension('ParserFunctions');
        $wgPFEnableStringFunctions = true;

        // MobileFrontend
        wfLoadExtension('MobileFrontend');
        $wgMFAutodetectMobileView = true;

        // Linked wiki
        wfLoadExtension('LinkedWiki');
        $wgLinkedWikiConfigDefaultEndpoint="https://query.wikidata.org/bigdata/namespace/wdq/sparql";

        // Gadgets
        wfLoadExtension('Gadgets');

        // Elasticsearch
        wfLoadExtension('Elastica');
        require_once "$IP/extensions/CirrusSearch/CirrusSearch.php";
        $wgCirrusSearchServers = array( 'mediawiki-elasticsearch' );
        $wgSearchType = 'CirrusSearch';
        $wgCirrusSearchUseCompletionSuggester = 'yes';

        // Semantic media wiki
        /*enableSemantics('wiki.x-truder.net');
        $smwgDefaultStore = 'SMWSparqlStore';
        $smwgSparqlDatabaseConnector = 'blazegraph';
        $smwgSparqlQueryEndpoint = 'http://wikibase-query-service:8000/bigdata/namespace/kb/sparql';
        $smwgSparqlUpdateEndpoint = 'http://wikibase-query-service:8000/bigdata/namespace/kb/sparql';
        $smwgSparqlDataEndpoint = ''';*/

        // Disable reading by anonymous users
        $wgGroupPermissions['*']['read'] = false;

        // But allow them to access the login page or else there will be no way to log in!
        // [You also might want to add access to "Main Page", "Help:Contents", etc.)
        $wgWhitelistRead = array ("Special:Userlogin", "Main Page");

        // Disable anonymous editing
        $wgGroupPermissions['*']['edit'] = false;

        // Prevent new user registrations except by sysops
        $wgGroupPermissions['*']['createaccount'] = false;

        // Dot not capitalize page titles
        $wgCapitalLinks = false;
      '';
    };
  };
}
