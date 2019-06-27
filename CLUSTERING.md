# 신경 clustering

A 신경 cluster tries to always be available, even in the face of a network
partition or other incident splitting it from other nodes. The way this is 
handled is simply that all nodes operate on whatever subset of the entire
cluster they can see. That is, in a cluster of 3 nodes, if they're somehow
split into groupings like `[A B] [C]`, nodes A and B will continue to handle
things based on what they can still see in the cluster, ie. the clients known
by nodes A and B. Node C will then effectively act like a single-node instance,
and only serve the clients it can still see. If the cluster reforms correctly, 
then all 3 nodes will handle input based off of the state of the full cluster.

The way that this is handled is that, rather than replicating client state and
metadata across the entire cluster, the work of running queries and proxying
HTTP requests and so on is done at a per-node level, and the results are
aggregated on the initiating node and then processed and returned to the
client.

For example, take a 3-node cluster `[A B C]` where every node has clients 
actively connected to it. If a client on node A wishes to send a message to a
service elsewhere in the cluster, the following will happen:

- the client sends a query + payload to node A
- node A will take the query and tell all nodes in the cluster - including
  itself - to run the query and return results in a map `%{node_name: results}`
- once the query has finished running on all nodes, a target is chosen from the
  pool of all potential matches via a random selection
- if the client is on a remote node, a message is sent to that node telling it
  to route a message to the specific client on that node
- if the client is on the local node - in this case, node A - the message is
  just sent directly to the client.

## Cluster formation

신경 clusters are Redis-backed, mainly because it was the easiest thing for me
to use at the time. When a 신경 node is running, it registers itself in a 
Redis-backed "node registry" of sorts, and other clients will constantly read
that registry and attempt to connect to any new nodes that are added. 

Node health-checks are quite simple in this case - if node A cannot reach node
B, node A will simply delete node B from the cluster. If node B is actually
still healthy, it will re-register itself for connections later. While this is
admittedly not the best way to form a consistent healthy cluster, I find that
it works for my needs and for the specific trade-offs that I choose to make.