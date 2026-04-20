[root@ip-10-240-146-214 nitaac-clean]# git log --oneline config/default/search_api.server.local.yml
267352021 NWD-91 - Fix local server settings
4ed49074f Set prod SOLR endpoint in main branch
c92111f66 Add CI/CD pipeline files and clean up settings
84d4407fe remove acquia_connector, acquia_search
[root@ip-10-240-146-214 nitaac-clean]#

git show 84d4407fe:config/default/search_api.server.local.yml | grep -E "host:|core:|id:|name:"


[root@ip-10-240-146-214 nitaac-clean]# git show 84d4407fe:config/default/search_api.server.local.yml | grep -E "host:|core:|id:|name:"
uuid: 8f95b609-40ff-47bf-80ee-e9019582865d
id: local
name: local
    host: solr
    core: dev
[root@ip-10-240-146-214 nitaac-clean]#
