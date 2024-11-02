#!/usr/bin/python
import os


CODE_ROOT = os.path.abspath(os.path.dirname(__file__))
QS_FILE = os.path.join(CODE_ROOT, 'queries.sql')
Q_DIR = os.path.join(CODE_ROOT, 'Q')
XML_DIR = os.path.join(CODE_ROOT, 'xml')

template = '''<test>
    <preconditions>
        <table_exists>hits</table_exists>
    </preconditions>

    <query><![CDATA[{query}]]></query>
</test>
'''


with open(QS_FILE) as fp:
    index = 0
    for line in fp.readlines():
        q_file = os.path.join(Q_DIR, str(index))
        xml_file = os.path.join(XML_DIR, str(index) + '.xml')
        with open(q_file, mode='w', encoding='utf-8') as ofp:
            ofp.write(line)
        with open(xml_file, mode='w', encoding='utf-8') as ofp:
            buf = template.format(query=line.strip())
            ofp.write(buf)
        index += 1
