echo "deleting mongo database"
mongo WorkspaceBuild --eval "db.dropDatabase()"

echo "deleting db-path"
rm -r /disks/p3/workspace/P3WSDB/

