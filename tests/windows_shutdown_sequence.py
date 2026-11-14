"""Print matched manual-gated extended trial commands; never drives a client.

Append one phase to a fresh trial's command file only after observing real
gameplay. After initial/map change, wait for real gameplay again. After the
after-map phase, reconnect the real client and observe gameplay before final.
Use the same phases without --profile for the no-profile control.
"""
import argparse

def commands(phase, active):
    def profile(lag, loss, mode):
        return f'cf_shutdown_profile {lag if active else 0} {loss if active else 0} {mode}'
    if phase == 'initial':
        lines = ['sm plugins load disabled/windows_shutdown_consumer', 'sm_custom_fakelag_debug 1',
                 profile(120, 0, 0), '@wait 5', profile(120, 10, 0), '@wait 5',
                 profile(120, 10, 1), '@wait 5', profile(0, 100, 1), '@wait 2',
                 'cf_shutdown_reset', '@wait 2']
        for _ in range(3):
            lines += ['sm_custom_fakelag_debug 1', profile(5000, 0, 0), '@wait 2', '@reload_cf']
        return lines + ['sm_custom_fakelag_debug 1', profile(5000, 0, 0), '@wait 2',
                        'changelevel c1m2_streets', '@wait 10', 'status', 'cf_shutdown_state']
    if phase == 'after-map':
        return ['cf_shutdown_state', 'sm_custom_fakelag_debug 1', profile(5000, 0, 0),
                '@wait 2', '@disconnect_human', 'cf_shutdown_state']
    return ['cf_shutdown_state', 'sm_custom_fakelag_debug 1', profile(120, 0, 0), '@run']

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('phase', choices=('initial', 'after-map', 'after-reconnect'))
    p.add_argument('--profile', action='store_true')
    a = p.parse_args()
    print('\n'.join(commands(a.phase, a.profile)))
