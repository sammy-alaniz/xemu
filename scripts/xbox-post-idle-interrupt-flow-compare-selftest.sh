#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-post-idle-irq-flow.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=native-headless seq=377 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 probe=after-idle-transition-sample stream_idle=yes stream_idle_seq=377 loop_kind=fallthrough start_pc=0x8001b02f next_pc=0x8001b030 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 main-loop=timers context=native-headless source=main-loop-wait seq=1 timer_progress=yes eip=0x8001b030 cpu_interrupt_request=0x00000002
BOOT_MARK b6 pic=irq-line context=native-headless seq=1 chip=master irq=0 guest_irq=0 level=assert output_irq=0 irr_before=0x00 irr_after=0x01 last_irr_before=0x00 last_irr_after=0x01 imr=0x92 isr=0x00 elcr=0x68 eip=0x8001b030
BOOT_MARK b6 cpu=hard-irq context=native-headless seq=1 op=reset request_before=0x00000002 request_after=0x00000000 eip=0x8001b030
BOOT_MARK b6 pic=irq-ack context=native-headless seq=1 intno=0x30 guest_irq=0 master_irq=0 slave_irq=-1 master_irr_before=0x01 master_irr_after=0x00 master_imr=0x92 master_isr_before=0x00 master_isr_after=0x00 master_elcr=0x68 slave_irr_before=0x00 slave_irr_after=0x00 slave_imr=0xff slave_isr_before=0x00 slave_isr_after=0x00 slave_elcr=0x00
BOOT_MARK b6 cpu=hard-irq-service context=native-headless seq=1 phase=before intno=0x30 eip=0x8001b030 stack_hash=0x864cefec5123c4f4 stack0=0x5e600200
BOOT_MARK b6 cpu=hard-irq-service context=native-headless seq=2 phase=after intno=0x30 eip=0x80030e4c stack_hash=0x455d94af83816994 stack0=0x8001b030
BOOT_MARK b6 cpu=iret context=native-headless seq=1 phase=before eip=0x800143f7 stack_hash=0x455d94af83816994 stack0=0x8001b030
BOOT_MARK b6 cpu=iret context=native-headless seq=2 phase=after eip=0x8001b030 stack_hash=0x864cefec5123c4f4 stack0=0x5e600200
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=2 probe=after-idle-transition-sample stream_idle=yes stream_idle_seq=377 loop_kind=forward start_pc=0x80030e84 next_pc=0x8001b030 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 cpu=hard-irq-service context=native-headless seq=3 phase=before intno=0x30 eip=0x8001b030 stack_hash=0x864cefec5123c4f4 stack0=0x5e600200
BOOT_MARK b6 cpu=hard-irq-service context=native-headless seq=4 phase=after intno=0x30 eip=0x80030e4c stack_hash=0x455d94af83816994 stack0=0x8001b030
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=browser-runtime seq=379 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 tcg=timer-pump context=browser-runtime seq=1 mode=idle-loop timer_progress=yes eip=0x8001b02f cpu_interrupt_request=0x00000002
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 probe=after-idle-transition-sample stream_idle=yes stream_idle_seq=379 loop_kind=fallthrough start_pc=0x8001b02f next_pc=0x8001b030 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000002 pending_interrupt=yes
BOOT_MARK b6 xbox-pm=evt-write context=browser-runtime seq=1 op=en addr=0x02 value=0x0000000000000101 width=2 pm1_sts_before=0x0100 pm1_sts_after=0x0100 pm1_sts_delta=0x0000 pm1_en_before=0x0001 pm1_en_after=0x0101 pm1_en_delta=0x0100 pm1_masked_after=0x0100 overflow_before=16777216 overflow_after=16777216 timer_enabled_after=no watch=yes eip=0x8001b030
BOOT_MARK b6 xbox-pm=tmr-callback context=browser-runtime seq=1 phase=callback virtual_now_ns=123456 timer_ticks=2147483648 overflow_time=2147483648 pm1_sts_before=0x0000 pm1_sts_after=0x0100 pm1_en=0x0101 pm1_masked_after=0x0100 watch=yes timer_pump_active=yes timer_pump_seq=1 timer_pump_observed_tbs=500 timer_pump_interval_tbs=1 timer_pump_now_before=123000 timer_pump_deadline_before=456 timer_pump_has_timers_before=yes timer_pump_expired_before=yes eip=0x8001b030
BOOT_MARK b6 xbox-pm=sci-update context=browser-runtime seq=1 reason=pm1-update sci_level=assert pm1_sts=0x0100 pm1_en=0x0101 pm1_masked=0x0100 gpe0_sts=0x00 gpe0_en=0x00 gpe0_masked=0x00 overflow_time=2147483648 timer_enabled=no watch=yes timer_pump_active=yes timer_pump_seq=1 timer_pump_observed_tbs=500 timer_pump_interval_tbs=1 timer_pump_now_before=123000 timer_pump_deadline_before=456 timer_pump_has_timers_before=yes timer_pump_expired_before=yes eip=0x8001b030
BOOT_MARK b6 ac97=bm-write context=browser-runtime seq=1 reg=cr bm_index=1 addr=0x1b value=0x00000011 width=1 bdbar_before=0x00100000 bdbar_after=0x00100000 civ_before=3 civ_after=4 lvi_before=4 lvi_after=4 piv_before=4 piv_after=5 sr_before=0x0001 sr_after=0x0000 cr_before=0x00 cr_after=0x11 picb_before=0 picb_after=32 bd_addr_before=0x00000000 bd_addr_after=0x00200000 bd_ctl_len_before=0x00000000 bd_ctl_len_after=0x80000020 bd_valid_before=no bd_valid_after=yes watch=yes eip=0x8001b030
BOOT_MARK b6 ac97=callback context=browser-runtime seq=1 callback=po bm_index=1 free_or_avail=128 sr=0x0000 cr=0x11 civ=4 lvi=4 piv=5 picb=32 bdbar=0x00100000 bd_addr=0x00200000 bd_ctl_len=0x80000020 bd_ioc=yes bd_bup=no bd_valid=yes watch=yes timer_pump_active=yes timer_pump_seq=1 timer_pump_observed_tbs=500 timer_pump_interval_tbs=1 timer_pump_now_before=123000 timer_pump_deadline_before=456 timer_pump_has_timers_before=yes timer_pump_expired_before=yes eip=0x8001b030
BOOT_MARK b6 ac97=transfer context=browser-runtime seq=1 bm_index=1 phase=descriptor-complete elapsed_remaining=0 temp=64 stop=yes sr_before=0x0000 sr_after=0x000d cr=0x11 civ=4 lvi=4 piv=5 picb=0 bdbar=0x00100000 bd_addr=0x00200000 bd_ctl_len=0x80000020 bd_ioc=yes bd_bup=no bd_valid=yes watch=yes timer_pump_active=yes timer_pump_seq=1 timer_pump_observed_tbs=500 timer_pump_interval_tbs=1 timer_pump_now_before=123000 timer_pump_deadline_before=456 timer_pump_has_timers_before=yes timer_pump_expired_before=yes eip=0x8001b030
BOOT_MARK b6 ac97=irq-update context=browser-runtime seq=1 bm_index=1 sr_before=0x0001 sr_after=0x000d old_mask=0x0000 new_mask=0x000c cr=0x11 glob_sta_before=0x00000000 glob_sta_after=0x00000040 event=yes level=assert civ=4 lvi=4 piv=5 picb=0 bdbar=0x00100000 bd_addr=0x00200000 bd_ctl_len=0x80000020 bd_valid=yes watch=yes timer_pump_active=yes timer_pump_seq=1 timer_pump_observed_tbs=500 timer_pump_interval_tbs=1 timer_pump_now_before=123000 timer_pump_deadline_before=456 timer_pump_has_timers_before=yes timer_pump_expired_before=yes eip=0x8001b030
BOOT_MARK b6 lpc=irq-route context=browser-runtime seq=1 source=usb1 route_type=internal input_irq=1 pic_irq=12 level=assert delivered=yes acpi_route=0x00000000 int_route=0x0e0654c1 pirq_route=0x00031000 watch=yes eip=0x8001b030
BOOT_MARK b6 pic=irq-line context=browser-runtime seq=1 chip=slave irq=4 guest_irq=12 level=assert output_irq=4 irr_before=0x00 irr_after=0x10 last_irr_before=0x00 last_irr_after=0x10 imr=0xa6 isr=0x00 elcr=0x18 eip=0x8001b030
BOOT_MARK b6 cpu=hard-irq context=browser-runtime seq=1 op=reset request_before=0x00000002 request_after=0x00000000 eip=0x8001b030
BOOT_MARK b6 pic=irq-ack context=browser-runtime seq=1 intno=0x30 guest_irq=0 master_irq=0 slave_irq=-1 master_irr_before=0x01 master_irr_after=0x00 master_imr=0x92 master_isr_before=0x00 master_isr_after=0x00 master_elcr=0x68 slave_irr_before=0x00 slave_irr_after=0x00 slave_imr=0xff slave_isr_before=0x00 slave_isr_after=0x00 slave_elcr=0x00
BOOT_MARK b6 cpu=hard-irq-service context=browser-runtime seq=1 phase=before intno=0x30 eip=0x8001b030 stack_hash=0x864cefec5123c4f4 stack0=0x5e600200
BOOT_MARK b6 cpu=hard-irq-service context=browser-runtime seq=2 phase=after intno=0x30 eip=0x80030e4c stack_hash=0x455d94af83816994 stack0=0x8001b030
BOOT_MARK b6 pic=irq-ack context=browser-runtime seq=2 intno=0x3c guest_irq=12 master_irq=2 slave_irq=4 master_irr_before=0x04 master_irr_after=0x00 master_imr=0x92 master_isr_before=0x00 master_isr_after=0x04 master_elcr=0x68 slave_irr_before=0x10 slave_irr_after=0x00 slave_imr=0x00 slave_isr_before=0x00 slave_isr_after=0x10 slave_elcr=0x00
BOOT_MARK b6 cpu=hard-irq-service context=browser-runtime seq=3 phase=before intno=0x3c eip=0x80030e84 stack_hash=0x579cec81de2cb2b2 stack0=0x00000002
BOOT_MARK b6 cpu=hard-irq-service context=browser-runtime seq=4 phase=after intno=0x3c eip=0x80030c14 stack_hash=0xf9725f7ddcf7a31e stack0=0x80030e84
BOOT_MARK b6 cpu=iret context=browser-runtime seq=1 phase=before eip=0x800143f7 stack_hash=0x455d94af83816994 stack0=0x8001b030
BOOT_MARK b6 cpu=iret context=browser-runtime seq=2 phase=after eip=0x8001b030 stack_hash=0x864cefec5123c4f4 stack0=0x5e600200
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=2 probe=after-idle-transition-sample stream_idle=yes stream_idle_seq=379 loop_kind=forward start_pc=0x80030e84 next_pc=0x80030f31 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000 pending_interrupt=no
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_IDLE_INTERRUPT_FLOW_COMPARE_SELFTEST case=browser-extra-vector result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'POST_IDLE_INTERRUPT_FLOW_COMPARE result=pass' \
    'divergence=browser-extra-interrupt-vector' \
    'timer_divergence=browser-missing-main-loop-timer-progress' \
    'native_vectors=0x30,0x30' \
    'browser_vectors=0x30,0x3c' \
    'browser_extra_vectors=0x3c' \
    'native_extra_pic_ack_vectors=none' \
    'browser_extra_pic_ack_vectors=0x3c' \
    'browser_first_extra_pic_ack=ack:0x3c:guest=12:master=2:slave=4:mirr=0x04->0x00' \
    'browser_extra_pic_line_assert_irqs=12' \
    'browser_first_extra_pic_line_assert=line:12:assert:chip=slave:irq=4:irr=0x00->0x10' \
    'browser_extra_lpc_route_assert_irqs=12' \
    'browser_first_extra_lpc_route_assert=route:12:assert:source=usb1:route=internal:input=1:delivered=yes' \
    'native_pm_timer_events=0' \
    'browser_pm_timer_events=1' \
    'native_pm_timer_pump_active_events=0' \
    'browser_pm_timer_pump_active_events=1' \
    'browser_first_pm_timer=pm-timer:callback:ticks=2147483648:overflow=2147483648:sts=0x0000->0x0100:en=0x0101:masked=0x0100:eip=0x8001b030' \
    'native_pm_evt_write_events=0' \
    'browser_pm_evt_write_events=1' \
    'native_pm_evt_write_pump_active_events=0' \
    'browser_pm_evt_write_pump_active_events=0' \
    'browser_first_pm_evt_write=pm-write:en:addr=0x02:val=0x0000000000000101:sts=0x0100->0x0100:en=0x0001->0x0101:timer=no:eip=0x8001b030' \
    'native_pm_sci_events=0' \
    'browser_pm_sci_events=1' \
    'native_pm_sci_pump_active_events=0' \
    'browser_pm_sci_pump_active_events=1' \
    'browser_pm_sci_assert_reasons=pm1-update' \
    'browser_first_pm_sci_assert=pm:pm1-update:assert:pm1=0x0100/0x0101/0x0100:gpe0=0x00/0x00/0x00:timer=no:eip=0x8001b030' \
    'native_ac97_callback_events=0' \
    'browser_ac97_callback_events=1' \
    'native_ac97_callback_pump_active_events=0' \
    'browser_ac97_callback_pump_active_events=1' \
    'browser_first_ac97_callback=ac97-callback:po:bm=1:free=128:sr=0x0000:cr=0x11:civ=4:lvi=4:picb=32:bd=0x00200000/0x80000020:eip=0x8001b030' \
    'native_ac97_bm_write_events=0' \
    'browser_ac97_bm_write_events=1' \
    'native_ac97_bm_write_pump_active_events=0' \
    'browser_ac97_bm_write_pump_active_events=0' \
    'browser_first_ac97_bm_write=ac97-write:bm=1:reg=cr:val=0x00000011:bdbar=0x00100000->0x00100000:lvi=4->4:cr=0x00->0x11:sr=0x0001->0x0000:picb=0->32:bd=0x00200000/0x80000020:eip=0x8001b030' \
    'native_ac97_transfer_events=0' \
    'browser_ac97_transfer_events=1' \
    'native_ac97_transfer_pump_active_events=0' \
    'browser_ac97_transfer_pump_active_events=1' \
    'browser_first_ac97_transfer=ac97-transfer:bm=1:phase=descriptor-complete:sr=0x0000->0x000d:cr=0x11:civ=4:lvi=4:picb=0:bd=0x00200000/0x80000020:ioc=yes:eip=0x8001b030' \
    'native_ac97_irq_events=0' \
    'browser_ac97_irq_events=1' \
    'native_ac97_irq_pump_active_events=0' \
    'browser_ac97_irq_pump_active_events=1' \
    'browser_ac97_irq_assert_indices=1' \
    'browser_first_ac97_irq_assert=ac97:bm=1:assert:sr=0x0001->0x000d:mask=0x0000->0x000c:cr=0x11:glob=0x00000000->0x00000040:civ=4:lvi=4:picb=0:bd=0x00200000/0x80000020:eip=0x8001b030' \
    'native_pic_ack_vectors=0x30' \
    'browser_pic_ack_vectors=0x30,0x3c' \
    'native_pic_line_assert_irqs=0' \
    'browser_pic_line_assert_irqs=12' \
    'browser_lpc_route_assert_irqs=12' \
    'browser_first_pic_ack=ack:0x30:guest=0:master=0:slave=-1:mirr=0x01->0x00' \
    'native_first_service=svc:0x30:0x8001b030->0x80030e4c:ret=0x8001b030:hash=0x455d94af83816994' \
    'browser_first_service=svc:0x30:0x8001b030->0x80030e4c:ret=0x8001b030:hash=0x455d94af83816994' \
    'native_first_post_service_loop=loop:0x80030e84->0x8001b030' \
    'browser_first_post_service_loop=loop:0x80030e84->0x80030f31' \
    'native_timer_events=1' \
    'browser_timer_events=1' \
    'native_tcg_timer_events=0' \
    'browser_tcg_timer_events=1' \
    'native_tcg_timer_progress_events=0' \
    'browser_tcg_timer_progress_events=1' \
    'browser_first_tcg_timer=timer:tcg:idle-loop:pc=0x8001b02f:irq=0x00000002:progress=yes' \
    'browser_first_tcg_timer_progress=timer:tcg:idle-loop:pc=0x8001b02f:irq=0x00000002:progress=yes' \
    'native_main_loop_timer_events=1' \
    'native_main_loop_timer_sources=main-loop-wait' \
    'browser_main_loop_timer_events=0' \
    'browser_main_loop_timer_sources=none' \
    'native_main_loop_timer_progress_events=1' \
    'browser_main_loop_timer_progress_events=0' \
    'native_first_main_loop_timer=timer:main-loop:main-loop-wait:pc=0x8001b030:irq=0x00000002:progress=yes' \
    'native_first_main_loop_timer_progress=timer:main-loop:main-loop-wait:pc=0x8001b030:irq=0x00000002:progress=yes'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'POST_IDLE_INTERRUPT_FLOW_COMPARE_SELFTEST case=browser-extra-vector result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'POST_IDLE_INTERRUPT_FLOW_COMPARE_SELFTEST case=browser-extra-vector result=pass\n'

if "${script}" --native-log "${tmp_dir}/missing.log" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_IDLE_INTERRUPT_FLOW_COMPARE_SELFTEST case=missing-native result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'result=fail' "${out_path}"; then
    printf 'POST_IDLE_INTERRUPT_FLOW_COMPARE_SELFTEST case=missing-native result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

printf 'POST_IDLE_INTERRUPT_FLOW_COMPARE_SELFTEST case=missing-native result=pass\n'
printf 'POST_IDLE_INTERRUPT_FLOW_COMPARE_SELFTEST_RESULT result=pass cases=2\n'
