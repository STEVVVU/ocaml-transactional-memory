"""Validate all backend repeats and retain honest ranges, including failed rows."""
import csv
import json
import pathlib
import statistics
import sys


def summarize(root):
    groups = {}
    for path in sorted(root.glob('metrics-*.csv')):
        with path.open() as source:
            for row in csv.DictReader(source):
                if row['record_type'] != 'summary':
                    continue
                assert int(row['errors']) == 0, row
                assert int(row['successes']) == int(row['operations']), row
                assert float(row['elapsed_s']) > 0, row
                key = tuple(row[k] for k in ('backend', 'workload', 'domains', 'accounts'))
                groups.setdefault(key, []).append(row)
    assert groups, 'no metrics summaries'
    output = []
    for key, rows in sorted(groups.items()):
        assert len(rows) == 5 and {int(r['trial']) for r in rows} == set(range(5)), key
        item = dict(zip(('backend', 'workload', 'domains', 'accounts'), key))
        for field in ('elapsed_s', 'ops_per_s', 'p50_us', 'p95_us', 'p99_us',
                      'tl2_retries', 'cpu_s', 'allocated_words'):
            values = [float(row[field]) for row in rows]
            item[field] = dict(median=statistics.median(values), min=min(values), max=max(values))
        item['short_sample'] = min(float(row['elapsed_s']) for row in rows) < 0.1
        output.append(item)
    return output


if __name__ == '__main__':
    root = pathlib.Path(sys.argv[1])
    (root / 'metrics-summary.json').write_text(json.dumps(summarize(root), indent=2) + '\n')
