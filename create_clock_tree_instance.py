#!/usr/bin/env python3

from graph.core import *

from graph.load_xml import load_graph_types_and_instances
from graph.save_xml_stream import write_device_instance, write_edge_instance
import sys
import os
import math
import csv
import json

import os
appBase=os.path.dirname(os.path.realpath(__file__))

# src=appBase+"/clock_tree_graph_type.xml"
src=appBase+"/clock_tree_single_handlers_graph_type.xml"
(graphTypes,graphInstances)=load_graph_types_and_instances(src,src)

d=4
b=2
maxTicks=100

graphType=graphTypes["clock_tree"]
nodeType=graphType.device_types["node"]

instName="clock_{}_{}".format(d,b)

properties={"max_ticks":maxTicks}
# res=GraphInstance(instName, graphType, properties)

nodes={}

def create(res, rootPrefix, rootParent, drainPrefix, drainParent, depth):
    node=None
    dNode=None
    if depth==0:
        node=DeviceInstance(res, "{}_leaf".format(rootPrefix), nodeType, {"type":2}, None)
        res.add_device_instance(node)
        res.add_edge_instance(EdgeInstance(res,node,"tick_in",rootParent,"tick_out", None))
        res.add_edge_instance(EdgeInstance(res,drainParent,"tick_in",node,"tick_out",None))
    else:
        if depth==d:
            for i in range(b):
                child=create(res, "{}_{}".format(rootPrefix, i), rootParent, "{}_{}".format(drainPrefix, i), drainParent, depth-1)
        else:
            node=DeviceInstance(res, rootPrefix, nodeType, {"type":1, "fanout":b}, None)
            dNode=DeviceInstance(res, drainPrefix, nodeType, {"type":3, "fanout":b}, None)
            res.add_device_instance(node)
            res.add_device_instance(dNode)
            for i in range(b):
                child=create(res, "{}_{}".format(rootPrefix,i), node, "{}_{}".format(drainPrefix,i), dNode, depth-1)

        if depth!=d:
            res.add_edge_instance(EdgeInstance(res,node,"tick_in", rootParent, "tick_out", None))
            res.add_edge_instance(EdgeInstance(res,drainParent,"tick_in", dNode,"tick_out", None))

    return node

def save_graph(dst, graph):
    if isinstance(dst, str):
        with open(dst,"wt") as dstFile:
            save_graph(dstFile, graph)
    else:
        # Copy Graph Type from given file
        with open(src) as fp:
            lines = fp.read().split("\n")

        for l in lines:
            if not (l == '</Graphs>'):
                dst.write(l)
                dst.write('\n')

        # Graph Instance
        dst.write(' <GraphInstance id="{}" graphTypeId="{}">\n'.format(graph.id,graph.graph_type.id))
        if graph.properties:
            dst.write('   <Properties>\n')
            dst.write(json.dumps(graph.properties,indent=2)[1:-1])
            dst.write('\n')
            dst.write('   </Properties>\n')
        if graph.metadata:
            dst.write('   <MetaData>\n')
            dst.write(json.dumps(graph.metadata,indent=2)[1:-1])
            dst.write('\n')
            dst.write('   </MetaData>\n')
        dst.write('  <DeviceInstances>\n')
        for di in graph.device_instances.values():
            write_device_instance(dst,di)
        dst.write('  </DeviceInstances>\n')
        dst.write('  <EdgeInstances>\n')
        for ei in graph.edge_instances.values():
            write_edge_instance(dst,ei)
        dst.write('  </EdgeInstances>\n')
        dst.write(' </GraphInstance>\n')

        # Close Grpah declaration
        dst.write('</Graphs>\n')

def createInstance(filepath):
    instName="clock_{}_{}".format(d,b)
    res=GraphInstance(instName, graphType, properties)
    # Create root and drain
    root=DeviceInstance(res, "root", nodeType, {"type":0, "fanout":1}, None)
    drain=DeviceInstance(res, "drain", nodeType, {"type":4, "fanout":b}, None)
    res.add_device_instance(root)
    res.add_device_instance(drain)
    # Add ack from drain to root to restart the cycle
    res.add_edge_instance(EdgeInstance(res,root,"tick_in",drain,"tick_out",None))

    create(res, "root",root, "drain", drain ,d)

    if (filepath == ''):
        save_graph(sys.stdout, res)
    else:
        if os.path.exists(filepath):
            try:
                os.remove(filepath)
            except OSError, e:
                print ("Error: %s - %s." % (e.filename,e.strerror))
        save_graph(filepath, res)

if len(sys.argv)==2:
    csvfile=sys.argv[1]
    if not os.path.exists("graphs"):
        os.makedirs("graphs")
    with open(csvfile) as data:
        reader = csv.reader(data)
        for row in reader:
            print(row)
            d = int(row[0])
            b = int(row[1])
            f = "graphs/clock_tree_mirror_single_handler_{}_{}.xml".format(d, b)
            createInstance(f)
        exit ()
else:
    if len(sys.argv)>1:
        d=int(sys.argv[1])
    if len(sys.argv)>2:
        b=int(sys.argv[2])
    if len(sys.argv)>3:
        maxTicks=int(sys.argv[3])

    createInstance("")


