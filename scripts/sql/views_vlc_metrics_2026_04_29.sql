-- VLC view 보정 (Superset → Grafana 전환, 2026-04-29)
--
-- 배경
-- ----
-- 기존 v_vlc_* view 6종은 measurement='vlc_media_stats' + 레거시 field
-- (input_bitrate, demux_bitrate, frame_drop_rate, played_audio_buffers,
-- lost_audio_buffers, demux_corrupted, demux_discontinuity, read_bytes,
-- decoded_video, displayed_pictures, lost_pictures)을 가정했다.
--
-- 실제 chzzk-web-collector가 적재하는 데이터는
--   measurement='vlc_metrics'
--   field='vlc_input_bitrate' / 'vlc_demux_bitrate' / 'vlc_displayed' /
--         'vlc_decoded_video' / 'vlc_lost' / 'vlc_late'
-- 형식이라 모든 view가 0 row였다.
--
-- 본 파일은 v_vlc_bitrate / v_vlc_frame_drop_rate / v_vlc_video_frames
-- 3종을 실제 적재 스키마에 맞게 재작성한다. (Grafana cview-vlc-quality
-- dashboard에서 사용)
--
-- 멱등 (CREATE OR REPLACE) — 안전하게 반복 실행 가능.
--
-- 적용
--   docker exec -i chzzk-postgres psql -U chzzk -d chzzk_db < scripts/sql/views_vlc_metrics_2026_04_29.sql

-- ─────────────────────────────────────────────────────────────────────
-- v_vlc_bitrate : input/demux bitrate (1분 평균)
--   field 이름은 레거시 호환을 위해 'input_bitrate' / 'demux_bitrate'로
--   매핑한다.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_vlc_bitrate AS
SELECT
    v."time",
    v.channel_id,
    CASE v.field
        WHEN 'vlc_input_bitrate' THEN 'input_bitrate'
        WHEN 'vlc_demux_bitrate' THEN 'demux_bitrate'
        ELSE v.field
    END AS field,
    v.bitrate,
    COALESCE(l.channel_name, v.channel_id) AS channel_name
FROM (
    SELECT time_bucket('1 minute', "time") AS "time",
           channel_id,
           field,
           avg(value_num) AS bitrate
    FROM metric_influx_samples
    WHERE measurement = 'vlc_metrics'
      AND field IN ('vlc_input_bitrate', 'vlc_demux_bitrate')
    GROUP BY 1, 2, 3
) v
LEFT JOIN channel_name_lookup l ON l.channel_id = v.channel_id;

-- ─────────────────────────────────────────────────────────────────────
-- v_vlc_frame_drop_rate : 프레임 드롭율(%)
--   원천 데이터에 frame_drop_rate 필드가 없어 vlc_lost / vlc_displayed
--   누적값으로 계산한다.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_vlc_frame_drop_rate AS
WITH last_vals AS (
    SELECT time_bucket('1 minute', "time") AS bucket,
           channel_id, field,
           last(value_num, "time") AS v
    FROM metric_influx_samples
    WHERE measurement = 'vlc_metrics'
      AND field IN ('vlc_lost', 'vlc_displayed')
    GROUP BY 1, 2, 3
), agg AS (
    SELECT bucket AS "time", channel_id,
           max(v) FILTER (WHERE field = 'vlc_lost')      AS lost,
           max(v) FILTER (WHERE field = 'vlc_displayed') AS displayed
    FROM last_vals
    GROUP BY 1, 2
)
SELECT a."time", a.channel_id,
       CASE WHEN COALESCE(a.lost, 0) + COALESCE(a.displayed, 0) > 0
            THEN COALESCE(a.lost, 0) / (a.lost + a.displayed) * 100.0
            ELSE 0
       END AS frame_drop_rate,
       COALESCE(l.channel_name, a.channel_id) AS channel_name
FROM agg a
LEFT JOIN channel_name_lookup l ON l.channel_id = a.channel_id;

-- ─────────────────────────────────────────────────────────────────────
-- v_vlc_video_frames : decoded / displayed / lost 의 초당 변화율
--   누적값 → 1분 bucket의 lag 차이 / 60초로 frames_per_second 산출.
--   레거시 호환을 위해 field명을 decoded_video / displayed_pictures /
--   lost_pictures 로 변환.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_vlc_video_frames AS
WITH bucketed AS (
    SELECT time_bucket('1 minute', "time") AS bucket,
           channel_id, field,
           last(value_num, "time") AS v
    FROM metric_influx_samples
    WHERE measurement = 'vlc_metrics'
      AND field IN ('vlc_decoded_video', 'vlc_displayed', 'vlc_lost')
    GROUP BY 1, 2, 3
), calc AS (
    SELECT bucket AS "time", channel_id,
           CASE field
               WHEN 'vlc_decoded_video' THEN 'decoded_video'
               WHEN 'vlc_displayed'     THEN 'displayed_pictures'
               WHEN 'vlc_lost'          THEN 'lost_pictures'
           END AS field,
           GREATEST(v - lag(v) OVER (PARTITION BY channel_id, field
                                     ORDER BY bucket), 0) / 60.0
               AS frames_per_second
    FROM bucketed
)
SELECT c."time", c.channel_id, c.field, c.frames_per_second,
       COALESCE(l.channel_name, c.channel_id) AS channel_name
FROM calc c
LEFT JOIN channel_name_lookup l ON l.channel_id = c.channel_id;

-- ─────────────────────────────────────────────────────────────────────
-- Grafana read-only 권한 (idempotent)
-- ─────────────────────────────────────────────────────────────────────
GRANT SELECT ON v_vlc_bitrate, v_vlc_frame_drop_rate, v_vlc_video_frames TO grafana_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_reader;
