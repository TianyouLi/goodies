import os
import re

template = '''<test>
    <preconditions>
        <table_exists>lineorder_flat</table_exists>
    </preconditions>

    <query><![CDATA[{query}]]></query>
</test>
'''

script_dir = os.path.abspath(os.path.dirname(__file__))
query_dir = os.path.join(script_dir, 'Q')
xml_dir = os.path.join(script_dir, 'xml')


for q in os.listdir(query_dir):
    if not re.match(r'\d\.\d', q):
        continue
    xml_path = os.path.join(xml_dir, q + '.xml')
    query_path = os.path.join(query_dir, q)
    with open(query_path, encoding='utf-8') as ifp:
        data = ifp.read().strip()
        query_str = ' '.join(data.splitlines())
        output_str = template.format(query=query_str)
        with open(xml_path, mode='w', encoding='utf-8') as ofp:
            ofp.write(output_str)
