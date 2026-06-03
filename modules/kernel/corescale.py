#!/usr/bin/env python3
import os
import time
import subprocess
import enum
import argparse
import re

SYSFILE = '/sys/devices/system/cpu/cpu'
PERF_STAT = "perf stat -e task-clock,cycles,instructions,cycles:k,instructions:k,cycles:u,instructions:u"  # NOQA
CODE_DIR = os.path.abspath(os.path.dirname(__file__))
BENCH = os.path.join(CODE_DIR, 'bench_query.sh')
LAUNCH = os.path.join(CODE_DIR, '..', 'launch.sh')
QUERY_DIR = os.path.join(CODE_DIR, 'Q')
ANSI_ESCAPE = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
JUPTER_TMPL = os.path.join(CODE_DIR, 'onepager.ipynb.tmpl')


def execute(cmd, env={}, sync=True):
    print('Running cmd: ' + cmd)
    osenv = os.environ
    osenv.update(env)
    p = subprocess.Popen(cmd, shell=True, env=osenv,
                         stderr=subprocess.STDOUT, stdout=subprocess.PIPE)
    if sync:
        stdout, _ = p.communicate()
        buf = stdout.decode('utf-8')
        print('OUTPUT:\n', buf)
        return ANSI_ESCAPE.sub('', buf)
    else:
        return p


def read_sys(sys_path):
    with open(sys_path) as fp:
        return fp.read().strip()


def parse_cpuset(cpuset_str):
    cpus = []
    for part in cpuset_str.split(','):
        if '-' in part:  # range likes: 5-8
            start, end = part.split('-')
            cpus.extend(range(int(start), int(end) + 1))
        else:  # normal cpu num
            cpus.append(int(part))
    return cpus

# Print iterations progress
def printProgressBar (iteration, total, prefix = '', suffix = '', decimals = 1, length = 50, fill = '█', printEnd = "\r"):
    """
    Call in a loop to create terminal progress bar
    @params:
        iteration   - Required  : current iteration (Int)
        total       - Required  : total iterations (Int)
        prefix      - Optional  : prefix string (Str)
        suffix      - Optional  : suffix string (Str)
        decimals    - Optional  : positive number of decimals in percent complete (Int)
        length      - Optional  : character length of bar (Int)
        fill        - Optional  : bar fill character (Str)
        printEnd    - Optional  : end character (e.g. "\r", "\r\n") (Str)
    """
    percent = ("{0:." + str(decimals) + "f}").format(100 * (iteration / float(total)))
    filledLength = int(length * iteration // total)
    bar = fill * filledLength + '-' * (length - filledLength)
    print(f'\r{prefix} |{bar}| {percent}% {suffix}', end = printEnd)
    # Print New Line on Complete
    if iteration == total: 
        print()

class CPUManager(object):
    def __init__(self):
        self.cpu_ids = self.__get_cpu_ids()

    @staticmethod
    def __get_cpu_ids():
        ids = []
        pattern = re.compile(r'cpu(\d+)')
        cpus_sys_dir = '/sys/devices/system/cpu'
        for f in os.listdir(cpus_sys_dir):
            if pattern.match(f):
                ids.append(int(f[len('cpu'):]))
        return sorted(ids)

    @staticmethod
    def __set_enable(cpu_id, enable):
        cpufilename = SYSFILE + str(cpu_id) + '/online'

        online = '1' if enable else '0'

        cmd = 'echo {online} | sudo tee {cpufile} 2>&1 > /dev/null'.format(
            online=online, cpufile=cpufilename)
        subprocess.call(cmd, shell=True)

    def enable(self, cpuset_str):
        online_cpus = set(parse_cpuset(cpuset_str))
        # first enable online cpus
        num_onlines = len(online_cpus)
        start = 0
        for cpuid in online_cpus:
            if cpuid != 0:
                self.__set_enable(cpuid, True)
            start += 1
            printProgressBar(start, num_onlines, prefix = 'Onlining...\t', suffix = 'Complete')

        # disable other cpus
        num_offlines = len(self.cpu_ids) - num_onlines
        start = 0
        for i in self.cpu_ids:
            if i not in online_cpus:
                if i != 0:
                    self.__set_enable(i, False)
                    start += 1
                    printProgressBar(start, num_offlines, prefix = 'Offlining...\t', suffix = 'Complete')


class cpuinfo:
    num_sockets = 0
    num_cores_per_socket = 0
    num_processors_per_core = 0

    processors = []

    class status(enum.Enum):
        ONLINE = 1
        OFFLINE = 2

    def __init__(self) -> None:
        lscpu = subprocess.check_output("lscpu", shell=True).strip().decode()
        for line in lscpu.splitlines():
            key, value = list(map(str.strip, line.split(':', 1)))
            if (key.find('Socket(s)') != -1):
                self.num_sockets = int(value)
            elif (key == 'Core(s) per socket'):
                self.num_cores_per_socket = int(value)
            elif (key == 'Thread(s) per core'):
                self.num_processors_per_core = int(value)
            elif (key == 'CPU(s)'):
                self.num_processors = int(value)

        self.processors = [[[] for i in range(
            self.num_cores_per_socket)] for j in range(self.num_sockets)]

        # fix core_id not increase linear
        tmp = [{} for i in range(self.num_sockets)]
        for idx in range(self.num_processors):
            sys_root = SYSFILE + str(idx) + '/topology/'
            proc_id = idx
            core_id = int(read_sys(sys_root + 'core_id'))
            socket_id = int(read_sys(sys_root + 'physical_package_id'))
            same_cores = tmp[socket_id].get(core_id, [])
            same_cores.append(proc_id)
            tmp[socket_id][core_id] = same_cores

        # now fill the processors list
        for socket_id in range(self.num_sockets):
            # sorted core ids
            core_ids = sorted(tmp[socket_id].keys())
            for new_core_id in range(len(core_ids)):
                for proc_id in tmp[socket_id][core_ids[new_core_id]]:
                    self.processors[socket_id][new_core_id].append(proc_id)

    def dumpCpuInfo(self):
        print(self.num_sockets)
        print(self.num_cores_per_socket)
        print(self.num_processors_per_core)
        print(self.processors)

    def getOnOffProcList(self, n):
        on_list = []
        off_list = []

        total_proc = self.num_sockets * \
            self.num_cores_per_socket * self.num_processors_per_core
        if (n < 0 or n > total_proc or n % self.num_processors_per_core != 0):
            return on_list, off_list

        proc_per_socket = self.num_cores_per_socket * self.num_processors_per_core  # NOQA
        for s in range(self.num_sockets):
            cur_socket = self.processors[s]
            if n <= s * proc_per_socket:
                break
            elif n <= (s+1) * proc_per_socket:
                on_list += [p for c in cur_socket for p in c][0: n - s * proc_per_socket]  # NOQA
                break
            else:
                on_list += [p for c in cur_socket for p in c]
                continue

        for i in range(total_proc):
            if i not in on_list:
                off_list.append(i)

        return on_list, off_list

    def enable(self, cpuset_str):
        online_cpus = set(parse_cpuset(cpuset_str))
        # first enable online cpus
        for cpuid in online_cpus:
            self.switch_proc(cpuid, cpuinfo.status.ONLINE)
        # disable other cpus
        for i in range(self.num_sockets):
            for j in range(self.num_cores_per_socket):
                for k in range(self.num_processors_per_core):
                    cpuid = self.processors[i][j][k]
                    if cpuid not in online_cpus:
                        self.switch_proc(cpuid, cpuinfo.status.OFFLINE)

    @staticmethod
    def switch_proc(i, s: status):
        if (i == 0):
            return

        cpufilename = SYSFILE + str(i) + '/online'

        online = '1' if s == cpuinfo.status.ONLINE else '0'

        cmd = 'sudo echo {online} | sudo tee {cpufile} > /dev/null'.format(
            online=online, cpufile=cpufilename)
        subprocess.call(cmd, shell=True)

        # with open(cpufilename, 'w') as wr_cores:
        #    subprocess.run(echo_online, stdout=wr_cores)

        # if s == cpuinfo.status.ONLINE:
        #    wr_cores.write('1')
        # elif s == cpuinfo.status.OFFLINE:
        #    wr_cores.write('0')

    def config_procs(self, n):
        on_list, off_list = self.getOnOffProcList(n)
        print("core#:", n)
        print(on_list)
        print(off_list)
        # Re-enable cores results in decrese of freq
        # for p in on_list:
        #    cpuinfo.switch_proc(p, cpuinfo.status.ONLINE)

        # don't use offlline
        # for p in off_list:
        #     cpuinfo.switch_proc(p, cpuinfo.status.OFFLINE)
        return on_list

    @staticmethod
    def restore_procs():
        lscpu = subprocess.check_output("lscpu", shell=True).strip().decode()
        off_list = []
        for line in lscpu.splitlines():
            key, value = list(map(str.strip, line.split(':', 1)))
            if (key.find('Off-line CPU(s) list') != -1):
                # example: 0-2,4-5,7
                for seg in value.split(','):
                    if (seg.find('-') != -1):
                        beg, end = map(lambda x: int(x), seg.split('-'))
                        for i in range(beg, end + 1):
                            off_list.append(i)
                    else:
                        off_list.append(int(seg))

        for p in off_list:
            print(p)
            cpuinfo.switch_proc(p, cpuinfo.status.ONLINE)


class CGroup(object):
    group_name = '/test-ck'

    def __init__(self):
        uid = execute('id -un $USER')
        gid = execute('id -gn $USER')
        self.cpuset = None
        self.uid_gid = '%s:%s' % (uid.strip(), gid.strip())

    def create(self):
        cmd = 'sudo cgcreate -t {ugid} -a {ugid} -g cpuset,memory:{gname}'.format( # NOQA
            ugid=self.uid_gid,
            gname=self.group_name
        )
        execute(cmd)

    def delete(self):
        cmd = 'sudo cgdelete cpuset,memory:%s' % self.group_name
        execute(cmd)

    def config(self, cpuset):
        self.cpuset = cpuset
        execute('cgset -r cpuset.cpus={cpuset} {gname}'.format(
            cpuset=cpuset,
            gname=self.group_name
        ))
        execute('cgset -r cpuset.mems=0 {gname}'.format(gname=self.group_name))

    def exec_cmd_prefix(self):
        # FIXME: current cgroup-tools not works in c9s because of v2
        return "taskset -c " + self.cpuset
        # return 'cgexec -g cpuset:{gname}'.format(gname=self.group_name)


class CoreScale(object):
    PORT = 9000
    LOOPS = 100

    def __init__(self, result_folder, ck_data_root):
        self.result_folder = os.path.abspath(result_folder)
        self.queries = self.get_queries()
        self.ck_data_root = os.path.abspath(ck_data_root)
        self.cpu_manager = CPUManager()
        self.server_pid = -1

    def get_queries(self):
        queries = os.listdir(QUERY_DIR)
        return sorted(queries)

    def get_result_dir(self, core_count, query):
        path = os.path.join(self.result_folder, str(core_count), str(query))
        # make sure folder created
        os.system('mkdir -p ' + path)
        return path

    def get_result_files(self, core_count, query):
        ''' return (score, perf-stat) '''
        folder = self.get_result_dir(core_count, query)
        score = os.path.join(folder, 'score')
        stat = os.path.join(folder, 'perf-stat')
        return (score, stat)

    def get_report_dir(self, query):
        path = os.path.join(self.result_folder, 'reports', str(query))
        os.system('mkdir -p ' + path)
        return path

    def run_query(self, core_count, query):
        f_score, f_stat = self.get_result_files(core_count, query)
        pids_str = str(self.server_pid)
        cmd = ' '.join([
            PERF_STAT,
            # '-r 5',  # repeat 5 times
            '-p ' + pids_str,
            '-o %s' % f_stat,
            '%s %s' % (BENCH, query),
            '2> ' + f_score
        ])
        env = {
            'REPEAT': str(self.LOOPS),
            # avoid setting max_threads, it will affect score a lot in HT-enabled.
            # 'SETTINGS': 'max_threads=%s' % core_count,
        }
        execute(cmd, env)

    def get_clickhouse_pid(self):
        from query_perf import get_pid_by_port

        return get_pid_by_port(self.PORT)

    def restart_server(self, core_count, cpuset):
        # kill previous server
        cmd = ';'.join([
            'pkill clickhouse-serv',
            'sleep 5',
            'echo 3 | sudo tee /proc/sys/vm/drop_caches',
        ])
        execute(cmd)
        cg_run_prefix = 'taskset -c %s' % cpuset
        cmd = ';'.join([
            'cd ' + self.ck_data_root,
            # should not use no-log, otherwise, QueryProfiler is disabled
            # cg_run_prefix + ' ' + LAUNCH + ' ref-no-log'  # disable log
            cg_run_prefix + ' ' + LAUNCH
        ])
        execute(cmd, sync=False)
        time.sleep(5)
        self.server_pid = self.get_clickhouse_pid()

    def warmup(self):
        # truncate metrics table
        exec_sql = os.path.join(CODE_DIR, '..', 'exec-sql-file.sh')
        sql_file = os.path.join(CODE_DIR, '..',
                                'sql', 'trunct_system_metrics.sql')
        execute(exec_sql + ' ' + sql_file)
        # run warmup query
        run_query = os.path.join(CODE_DIR, 'run_query.sh')
        execute(run_query + ' all > /dev/null', {'REPEAT': '10'})
        time.sleep(20)  # wait for server backgrournd job done

    def do_scale(self, core_count, cpuset):
        # set core num
        self.cpu_manager.enable(cpuset)
        # restart and launch server
        self.restart_server(core_count, cpuset)
        # warmup
        self.warmup()
        # doing real test
        for q in self.queries:
            self.run_query(core_count, q)
            time.sleep(1)

    def run(self, corescale_conf):
        with open(corescale_conf) as fp:
            for line in fp.readlines():
                # core_count, cpuset
                core_count, cpuset = line.split()
                self.do_scale(core_count, cpuset)

    def parse_bench(self, buf):
        qps_list = []
        keyword = 'queries: %d' % self.LOOPS
        for line in buf.splitlines():
            if keyword in line:
                parts = line.split(',')
                qps_item = parts[2]
                qps = float(qps_item.split()[1])
                qps_list.append(qps)
        return sum(qps_list)/len(qps_list)

    def get_score(self, core_count, query):
        score_file, _ = self.get_result_files(core_count, query)
        with open(score_file) as fp:
            buf = fp.read()
            qps = self.parse_bench(buf)
            return qps

    def get_perf_stat(self, core_count, query):
        _, stat_file = self.get_result_files(core_count, query)
        data = {}
        with open(stat_file) as fp:
            for line in fp.readlines():
                if 'time elapsed' in line:
                    ts = float(line.split()[0])
                    data['seconds'] = ts
                    continue
                if 'cycles:k' in line:
                    ck = float(line.split()[0].replace(',', ''))
                    data['cycles:k'] = ck
                    continue
                if 'cycles:u' in line:
                    cu = float(line.split()[0].replace(',', ''))
                    data['cycles:u'] = cu
                    continue
                if '#' not in line or line.startswith('#'):
                    continue
                head = line.split('#')[0]
                parts = head.split()
                if 'msec' in line and 'task-clock' in line:
                    name = parts[2]
                else:
                    name = parts[1]
                if name.startswith('cpu_atom'):
                    # cpu_atom/cycles:u/
                    name = name[len('cpu_atom/'):-1]
                value = float(parts[0].replace(',', ''))
                data[name] = value
                if 'task-clock' in line:
                    tail = line.split('#')[1]
                    data['utilization'] = float(tail.split()[0])
        return data

    def generate_csv(self, query):
        # core number put in root of resut folder
        cores = sorted(map(int,
                           filter(str.isdigit,
                                  os.listdir(self.result_folder))))
        data = []
        for cnum in cores:
            score = self.get_score(cnum, query)
            perf_stat = self.get_perf_stat(cnum, query)
            data.append((cnum, score, perf_stat))

        base_score = data[0][1]
        csv_file = os.path.join(self.get_report_dir(query), 'summary.csv')
        with open(csv_file, 'w') as fp:
            header = ','.join([
                '# of Threads',
                'Clock(ms)',
                'CPU utilization(%)',
                'CYCLE',
                'INSTC',
                'IPC',
                'CYCLE(user)',
                'INSTC(user)',
                'IPC(user)',
                'CYCLE(kernel)',
                'INSTC(kernel)',
                'IPC(kernel)',
                'TPS',
                'Normalized Score (%)',
                'Normalized CPU Utilization (%)'
            ])
            fp.write(header + '\n')
            for d in data:
                stat = d[2]
                line = ','.join(map(str, [
                    d[0],
                    stat['task-clock'],
                    stat['utilization'],
                    stat['cycles'],
                    stat['instructions'],
                    stat['instructions']/stat['cycles'],
                    stat['cycles:u'],
                    stat['instructions:u'],
                    stat['instructions:u']/stat['cycles:u'],
                    stat['cycles:k'],
                    stat['instructions:k'],
                    stat['instructions:k']/stat['cycles:k'],
                    d[1],
                    d[1]*stat['cycles']/base_score/stat['task-clock']/1000000,  # normalized score
                    stat['utilization']/d[0],
                ]))
                fp.write(line + '\n')

    def generate_jupter(self, query):
        with open(JUPTER_TMPL) as fp:
            tmpl = fp.read()
        content = tmpl.replace('${{benchmark}}', 'ClickBench Benchmark')\
                      .replace('${{case_desc}}', 'Q%s' % query)\
                      .replace('${{case_link}}', '')\
                      .replace('${{case_prop}}', 'HIB')
        output_fpath = os.path.join(self.get_report_dir(query),
                                    'onepager.ipynb')
        with open(output_fpath, 'w') as fp:
            fp.write(content)
        # rendering notebooks
        cmd = 'jupyter nbconvert --to notebook --inplace --execute ' + output_fpath  # NOQA
        os.system(cmd)
        cmd = 'jupyter trust ' + output_fpath
        os.system(cmd)

    def report(self):
        for q in self.queries:
            self.generate_csv(q)
            self.generate_jupter(q)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="core scaling tools for CK")
    parser.add_argument('--output', dest='output_dir',
                        help='result folder for core scaling')
    parser.add_argument('--ck_root', dest='ck_root', default=None,
                        help='ClickHouse build root path.')
    parser.add_argument('--config', dest='config', default=None,
                        help='core scaling config file')
    parser.add_argument('--report', dest='report_only', action='store_true',
                        default=False, help='report only mode')
    parser.add_argument('--cpuset', dest='cpuset', default=None,
                        help='only enable cpuset online')
    args = parser.parse_args()

    if args.cpuset:
        cm = CPUManager()
        cm.enable(args.cpuset)
        exit(0)
    cs = CoreScale(args.output_dir, args.ck_root)
    if not args.report_only:
        cs.run(args.config)
    cs.report()
