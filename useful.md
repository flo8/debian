# Live check
sudo perf stat ./myprogram

# Record myprogram perforance
sudo perf record ./myprogram

# or record an existing PID
sudo perf record -p PID

# Inspect report
perf report

# Get public IP
myip
