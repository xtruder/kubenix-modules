{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.galera = {
    module = "galera";

    configuration = {
      storage.enable = true;
      rootPassword = "root";
      replicas = 1;
      user = "mediawiki";
      database = "mediawiki";
      password = "mediawiki";
    };
  };

  kubernetes.modules.elasticsearch = {
    module = "elasticsearch";

    configuration = {
      name = "escluster";
      nodeSets.nodes = {
        roles = ["master" "client" "data"];
        replicas = 1;
        storage = {
          enable = true;
          size = "50G";
        };
      };
    };
  };

  kubernetes.modules.mediawiki = {
    module = "mediawiki";

    configuration = {
      adminPassword = "A5jnbPUNU<\aqZm";
      url = "https://wiki.x-truder.net/";
      db.host = "galera";
      customConfig = ''
        $wgEnableUploads = true;

        // Network authentication
        require_once "$IP/extensions/NetworkAuth/NetworkAuth.php";

        // VisualEditor
        wfLoadExtension('VisualEditor');
        $wgDefaultUserOptions['visualeditor-enable'] = 1; // Enable by default for everybody
        $wgVisualEditorParsoidURL = "http://127.0.0.1:8000";
        $wgNetworkAuthUsers[] = array(
          'iprange' => array('127.0.0.1/32'),
          'user' => 'parsoid'
        );

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
        $wgCirrusSearchServers = array( 'elasticsearch' );
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
