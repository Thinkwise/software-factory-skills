# Worked example — remote control for an MQTT robot

A simulated cleaning robot on a grid publishes and listens on `robots/<robot_id>/…`. The Thinkwise
application drives it and shows its live state, including a "blocked" state when a move would hit
furniture or a wall.

## MQTT contract

| Topic | Direction | Retained | QoS | Payload |
|---|---|---|---|---|
| `robots/{robot_id}/cmd` | app → robot | no | 1 | `{"id":"TW-12","command":"move","direction":"E","steps":"1","x":"0","y":"0"}` |
| `robots/{robot_id}/state` | robot → app | yes | 0 | `{"x":4,"y":1,"heading":"E","status":"moving","current":"goto","target":{"x":9,"y":6},"queue":0,"docked":false}` — every step |
| `robots/{robot_id}/result` | robot → app | no | 1 | `{"id":"TW-12","command":"move","ok":false,"reason":"blocked","message":"Blocked by Table at (5,2)","x":4,"y":2,"heading":"E"}` |
| `robots/{robot_id}/status` | robot → app | yes | 1 | `online` / `offline` (offline is the Last Will) |
| `robots/{robot_id}/config` | robot → app | yes | 1 | grid size, dock, `obstacles: [{name,x,y,w,h}]` |

## Model

- **Tables:** `robot` (position, heading, moving, docked, blocked + blocked_by/x/y, last result, grid,
  timestamps; derived `robot_status` offline/idle/moving/blocked), `robot_obstacle`,
  `robot_visited_cell`, `robot_command` (identity id, `correlation_id`, status sent/succeeded/failed/
  blocked/cancelled, origin thinkwise/external), `mqtt_message_log`. A view `room_cell` generates every
  grid cell with its type for a clickable "Drive here" task; an HTML expression column draws the room.
- **Publish side:** message `robot_command` with inputs `robot_id, correlation_id, command, direction,
  step_count, x, y` (all quoted in the payload). Fourteen table tasks (move N/E/S/W, turn, forward,
  goto, dock, stop, reset, drive here) share one template that calls a subroutine to insert the command
  row, build `TW-<id>`, clear the blocked flag and normalize nulls; the user flow `send_robot_command`
  has all fourteen as starting points → one Publish message → stop.
- **Subscribe side:** four subscriptions, each with its own system flow `robot_<topic>_received` →
  Execute system task `process_robot_<topic>`:
  - state: `robot_id` from the topic parameter; `x`, `y`, `heading`, `status`, `current`, `target.x`,
    `target.y`, `queue`, `docked` via JSON paths (`docked` into a varchar `json_boolean` variable).
  - result: `id`, `command`, `ok` (varchar), `reason`, `message`, `x`, `y`, `heading`, plus the raw
    payload for the log; outputs `is_blocked`, `notify_user`, `notify_message` feed a decision and a
    Send user notification.
  - status: raw payload text. config: raw payload, unpacked with `openjson`.
- **Context:** drive tasks disabled while the robot is offline; "Drive here" only on free cells.
- **Conditional layouts:** blocked rows red, offline grey, the bumped cell red.

## Receiving-task SQL patterns

```sql
-- every receiving task: upsert the robot (retained messages arrive in any order)
if not exists (select 1
               from robot r
               where r.robot_id = @robot_id)
begin
    insert into robot (robot_id
                      ,online
                      ,is_moving
                      ,docked
                      ,blocked
                      ,queue_length
                      ,coverage_percentage)
    values (@robot_id
           ,0
           ,0
           ,0
           ,0
           ,0
           ,0)
end

-- state: JSON booleans arrive as text
update robot
set    x             = @x
      ,y             = @y
      ,heading       = @heading
      ,is_moving     = iif(@movement_status = 'moving', 1, 0)
      ,docked        = iif(@docked = 'true', 1, 0)
      ,last_state_at = sysutcdatetime()
where  robot_id = @robot_id

-- result: match the command by correlation id, else register an external command
declare @ok_bit     bit = iif(@ok = 'true', 1, 0)
       ,@command_id int

select @command_id = rc.command_id
from robot_command rc
where rc.robot_id       = @robot_id
  and rc.correlation_id = nullif(@correlation_id, '')

-- 'Blocked by Table at (5,2)' → blocked_by = Table, blocked_x = 5, blocked_y = 2
-- @blocked_by depends on @at, so it gets its own statement.
set @at = charindex(' at (', @message)
set @blocked_by = substring(@message, 12, @at - 12)

-- config: rebuild the obstacles from the raw payload
delete from robot_obstacle
where robot_id = @robot_id

insert into robot_obstacle (robot_id
                           ,obstacle_no
                           ,obstacle_name
                           ,x
                           ,y
                           ,width
                           ,height)
select @robot_id                  as robot_id
      ,cast(o.[key] as int) + 1   as obstacle_no
      ,j.name                     as obstacle_name
      ,j.x
      ,j.y
      ,isnull(j.w, 1)             as width
      ,isnull(j.h, 1)             as height
from openjson(@payload, '$.obstacles') o
cross apply openjson(o.value) with (name nvarchar(100) '$.name'
                                   ,x    int           '$.x'
                                   ,y    int           '$.y'
                                   ,w    int           '$.w'
                                   ,h    int           '$.h') j
```

## Checks that proved the setup end to end

- The device row appears within seconds of restarting Indicium (from the retained topics).
- A command button changes the robot in the device's own UI, and the command row goes sent → succeeded.
- Driving into furniture turns the robot and the command red, marks the bumped cell, and notifies the
  sender.
- Stopping the device process flips it to offline via the Last Will and disables the drive tasks.
