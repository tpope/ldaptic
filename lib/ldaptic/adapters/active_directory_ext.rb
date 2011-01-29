require 'date'

# Converts an integer representing the number of microseconds since January 1,
# 1600 to a DateTime.
def DateTime.microsoft(tinies)
  new(1601,1,1).new_offset(Time.now.utc_offset/60/60/24.0) + tinies/1e7/60/60/24
end

# Converts an integer representing the number of microseconds since January 1,
# 1600 to a Time.
def Time.microsoft(tinies)
  dt = DateTime.microsoft(tinies)
  Time.local(dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec,dt.sec_fraction*60*60*24*1e6)
end
