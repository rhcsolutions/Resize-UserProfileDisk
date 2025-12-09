/* eslint-disable no-unused-vars */
// Functions showTab, browsePath, browseFile, testConnection, submitResizeJob, refreshJobs, viewJobDetails, refreshLogs, refreshStats are called from HTML

// Configuration
const API_BASE = '';
let refreshInterval = null;

// Expose functions to global scope for HTML onclick handlers
window.showTab = showTab;
window.browsePath = browsePath;
window.browseFile = browseFile;
window.testConnection = testConnection;
window.submitResizeJob = submitResizeJob;
window.refreshJobs = refreshJobs;
window.viewJobDetails = viewJobDetails;
window.refreshLogs = refreshLogs;
window.refreshStats = refreshStats;
window.toggleMode = toggleMode;

// Utility Functions
function showNotification(message, type = 'info') {
    const notification = document.getElementById('notification');
    notification.textContent = message;
    notification.className = `notification ${type}`;
    notification.style.display = 'block';
    
    setTimeout(() => {
        notification.style.display = 'none';
    }, 5000);
}

function formatDateTime(dateString) {
    const date = new Date(dateString);
    return date.toLocaleString();
}

function formatDuration(startDate, endDate) {
    if (!startDate || !endDate) return '-';
    const start = new Date(startDate);
    const end = new Date(endDate);
    const diff = end - start;
    const minutes = Math.floor(diff / 60000);
    const seconds = Math.floor((diff % 60000) / 1000);
    return `${minutes}m ${seconds}s`;
}

function formatUptime(uptime) {
    const days = Math.floor(uptime.Days);
    const hours = Math.floor(uptime.Hours);
    const minutes = Math.floor(uptime.Minutes);
    
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
}

// Tab Management
// Called from HTML onclick handlers
function showTab(tabName) {
    const tabs = document.querySelectorAll('.tab-content');
    const buttons = document.querySelectorAll('.tab-button');
    
    tabs.forEach(tab => { tab.classList.remove('active'); });
    buttons.forEach(btn => { btn.classList.remove('active'); });
    
    document.getElementById(tabName).classList.add('active');
    event.target.classList.add('active');
    
    // Load data for the tab
    switch(tabName) {
        case 'jobs':
            refreshJobs();
            break;
        case 'logs':
            refreshLogs();
            break;
        case 'stats':
            refreshStats();
            break;
    }
}

// Form Management
function toggleMode() {
    const mode = document.querySelector('input[name="mode"]:checked').value;
    const pathInput = document.getElementById('pathInput');
    const singleFileInput = document.getElementById('singleFileInput');
    const browseFileBtn = document.getElementById('browseFileBtn');
    
    if (mode === 'path') {
        pathInput.disabled = false;
        pathInput.required = true;
        singleFileInput.disabled = true;
        singleFileInput.required = false;
        browseFileBtn.disabled = true;
    } else {
        pathInput.disabled = true;
        pathInput.required = false;
        singleFileInput.disabled = false;
        singleFileInput.required = true;
        browseFileBtn.disabled = false;
    }
}

// Called from HTML onclick handler
function browsePath() {
    const pathInput = document.getElementById('pathInput');
    const currentPath = pathInput.value || 'D:\\UPD';
    const newPath = prompt('Enter the full path to the UPD folder:', currentPath);
    if (newPath) {
        pathInput.value = newPath;
    }
}

// Called from HTML onclick handler
function browseFile() {
    const fileInput = document.getElementById('singleFileInput');
    const currentPath = fileInput.value || 'D:\\UPD\\UVHD-S-1-5-21-xxx.vhdx';
    const newPath = prompt('Enter the full path to the VHDX file:', currentPath);
    if (newPath) {
        fileInput.value = newPath;
    }
}

// API Calls
// Called from HTML onclick handler
async function testConnection() {
    try {
        const response = await fetch(`${API_BASE}/api/status`);
        if (response.ok) {
            showNotification('Connection successful!', 'success');
            updateServiceStatus();
        } else {
            showNotification('Connection failed!', 'error');
        }
    } catch (error) {
        showNotification(`Connection error: ${error.message}`, 'error');
    }
}

async function updateServiceStatus() {
    try {
        const response = await fetch(`${API_BASE}/api/status`);
        if (response.ok) {
            const status = await response.json();
            const statusElement = document.getElementById('serviceStatus');
            statusElement.textContent = `🟢 Service Running | Jobs: ${status.TotalJobs}`;
            
            if (status.CurrentJob) {
                const currentJobElement = document.getElementById('currentJob');
                currentJobElement.textContent = `Current Job: ${status.CurrentJob}`;
                updateCurrentJob(status.CurrentJob);
            }
            
            return status;
        } else {
            document.getElementById('serviceStatus').textContent = '🔴 Service Offline';
        }
    } catch (error) {
        console.error('Service status check failed:', error);
        document.getElementById('serviceStatus').textContent = '🔴 Connection Error';
    }
}

async function updateCurrentJob(jobId) {
    try {
        const response = await fetch(`${API_BASE}/api/jobs/${jobId}`);
        if (response.ok) {
            const job = await response.json();
            const card = document.getElementById('currentJobCard');
            const details = document.getElementById('currentJobDetails');
            
            card.style.display = 'block';
            
            details.innerHTML = `
                <div class="job-details">
                    <div class="job-details-grid">
                        <div class="job-detail-item">
                            <div class="job-detail-label">Status</div>
                            <div class="job-detail-value">
                                <span class="status-badge status-${job.Status.toLowerCase()}">${job.Status}</span>
                            </div>
                        </div>
                        <div class="job-detail-item">
                            <div class="job-detail-label">Path</div>
                            <div class="job-detail-value">${job.Path || job.SingleVhdxFile}</div>
                        </div>
                        <div class="job-detail-item">
                            <div class="job-detail-label">Progress</div>
                            <div class="job-detail-value">${job.ProcessedFiles} / ${job.TotalFiles}</div>
                        </div>
                        <div class="job-detail-item">
                            <div class="job-detail-label">Space Saved</div>
                            <div class="job-detail-value">${job.Savings.toFixed(2)} GB</div>
                        </div>
                    </div>
                    ${job.Progress > 0 ? `
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: ${job.Progress}%"></div>
                        </div>
            ` : ''}
        </div>
    `;
        }
    } catch (error) {
        console.error('Error fetching current job:', error);
    }
}async function submitResizeJob(event) {
    event.preventDefault();
    
    const mode = document.querySelector('input[name="mode"]:checked').value;
    const formData = {
        path: mode === 'path' ? document.getElementById('pathInput').value : null,
        singleFile: mode === 'single' ? document.getElementById('singleFileInput').value : null,
        includeTemplate: document.getElementById('includeTemplate').checked,
        defrag: document.getElementById('defrag').checked,
        zeroFreeSpace: document.getElementById('zeroFreeSpace').checked
    };
    
    try {
        const response = await fetch(`${API_BASE}/api/jobs`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(formData)
        });
        
        if (response.ok) {
            const job = await response.json();
            showNotification(`Job created successfully! Job ID: ${job.JobId}`, 'success');
            document.getElementById('resizeForm').reset();
            toggleMode();
            
            // Switch to jobs tab
            document.querySelector('[onclick="showTab(\'jobs\')"]').click();
        } else {
            const error = await response.json();
            showNotification(`Failed to create job: ${error.error}`, 'error');
        }
    } catch (error) {
        showNotification(`Error: ${error.message}`, 'error');
    }
}

async function refreshJobs() {
    const statusFilter = document.getElementById('jobStatusFilter')?.value || '';
    
    try {
        const response = await fetch(`${API_BASE}/api/jobs`);
        if (response.ok) {
            const jobs = await response.json();
            const tbody = document.getElementById('jobsTableBody');
            
            let filteredJobs = jobs;
            if (statusFilter) {
                filteredJobs = jobs.filter(j => j.Status === statusFilter);
            }
            
            if (filteredJobs.length === 0) {
                tbody.innerHTML = '<tr><td colspan="8" class="loading">No jobs found</td></tr>';
                return;
            }
            
            tbody.innerHTML = filteredJobs.map(job => `
                <tr>
                    <td><code>${job.JobId.substring(0, 8)}</code></td>
                    <td><span class="status-badge status-${job.Status.toLowerCase()}">${job.Status}</span></td>
                    <td>${job.Path || job.SingleVhdxFile || '-'}</td>
                    <td>${formatDateTime(job.CreatedAt)}</td>
                    <td>${formatDuration(job.StartedAt, job.CompletedAt)}</td>
                    <td>${job.ProcessedFiles} / ${job.TotalFiles}</td>
                    <td>${job.Savings.toFixed(2)}</td>
                    <td>
                        <button class="btn-secondary" onclick="viewJobDetails('${job.JobId}')">View</button>
                    </td>
                </tr>
            `).join('');
        }
    } catch (error) {
        console.error('Error fetching jobs:', error);
        showNotification('Failed to load jobs', 'error');
    }
}

// Called from HTML onclick handler
async function viewJobDetails(jobId) {
    try {
        const response = await fetch(`${API_BASE}/api/jobs/${jobId}`);
        if (response.ok) {
            const job = await response.json();
            
            const details = `
Job ID: ${job.JobId}
Status: ${job.Status}
Path: ${job.Path || job.SingleVhdxFile}
Created: ${formatDateTime(job.CreatedAt)}
Started: ${job.StartedAt ? formatDateTime(job.StartedAt) : 'Not started'}
Completed: ${job.CompletedAt ? formatDateTime(job.CompletedAt) : 'Not completed'}
Duration: ${formatDuration(job.StartedAt, job.CompletedAt)}

Files: ${job.ProcessedFiles} / ${job.TotalFiles}
Size Before: ${job.SizeBefore.toFixed(2)} GB
Size After: ${job.SizeAfter.toFixed(2)} GB
Savings: ${job.Savings.toFixed(2)} GB

Options:
- Include Template: ${job.IncludeTemplate ? 'Yes' : 'No'}
- Defrag: ${job.Defrag ? 'Yes' : 'No'}
- Zero Free Space: ${job.ZeroFreeSpace ? 'Yes' : 'No'}

${job.Errors.length > 0 ? '\nErrors:\n' + job.Errors.join('\n') : ''}
            `;
            
            alert(details);
        }
    } catch (error) {
        console.error('Error fetching job details:', error);
        showNotification('Failed to load job details', 'error');
    }
}

async function refreshLogs() {
    const severityFilter = document.getElementById('logSeverityFilter')?.value || '';
    const jobIdFilter = document.getElementById('logJobIdFilter')?.value || '';
    const count = document.getElementById('logCountFilter')?.value || '100';
    
    try {
        let url = `${API_BASE}/api/logs?count=${count}`;
        if (severityFilter) url += `&severity=${severityFilter}`;
        if (jobIdFilter) url += `&jobId=${jobIdFilter}`;
        
        const response = await fetch(url);
        if (response.ok) {
            const logs = await response.json();
            const container = document.getElementById('logsContainer');
            
            if (logs.length === 0) {
                container.innerHTML = '<div class="loading">No logs found</div>';
                return;
            }
            
            container.innerHTML = logs.map(log => `
                <div class="log-entry ${log.Severity.toLowerCase()}">
                    <span class="log-timestamp">${log.Timestamp}</span>
                    <span class="log-severity">[${log.Severity}]</span>
                    <span class="log-message">[${log.JobId}] ${log.Message}</span>
                </div>
            `).join('');
        }
    } catch (error) {
        console.error('Error fetching logs:', error);
        showNotification('Failed to load logs', 'error');
    }
}

async function refreshStats() {
    try {
        const response = await fetch(`${API_BASE}/api/status`);
        if (response.ok) {
            const status = await response.json();
            
            document.getElementById('statUptime').textContent = formatUptime(status.Uptime);
            document.getElementById('statTotalJobs').textContent = status.TotalJobs;
            document.getElementById('statCompleted').textContent = status.CompletedJobs;
            document.getElementById('statFailed').textContent = status.FailedJobs;
            document.getElementById('statRunning').textContent = status.RunningJobs;
            document.getElementById('statQueued').textContent = status.QueuedJobs;
        }
    } catch (error) {
        console.error('Error fetching stats:', error);
    }
}

// Event Listeners
document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('resizeForm').addEventListener('submit', submitResizeJob);
    
    // Initial load
    updateServiceStatus();
    
    // Auto-refresh every 5 seconds
    refreshInterval = setInterval(() => {
        updateServiceStatus();
        
        const activeTab = document.querySelector('.tab-content.active');
        if (activeTab) {
            switch(activeTab.id) {
                case 'jobs':
                    refreshJobs();
                    break;
                case 'logs':
                    refreshLogs();
                    break;
                case 'stats':
                    refreshStats();
                    break;
            }
        }
    }, 5000);
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (refreshInterval) {
        clearInterval(refreshInterval);
    }
});
