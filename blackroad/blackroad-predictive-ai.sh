#!/bin/bash
# BlackRoad Predictive AI System
# Predict failures before they happen

PREDICTIVE_VERSION="2.0.0"
STATE_DIR="$HOME/.blackroad/predictive"
MODELS_DIR="$STATE_DIR/models"
PREDICTIONS_DIR="$STATE_DIR/predictions"
TRAINING_DIR="$STATE_DIR/training"

mkdir -p "$MODELS_DIR" "$PREDICTIONS_DIR" "$TRAINING_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Collect metrics for prediction
collect_metrics() {
    local metrics_file="$TRAINING_DIR/metrics-$(date +%s).json"

    # GitHub metrics
    local gh_rate_limit=$(gh api rate_limit -q '.rate.remaining' 2>/dev/null || echo "0")
    local gh_rate_limit_reset=$(gh api rate_limit -q '.rate.reset' 2>/dev/null || echo "0")

    # System metrics
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
    local memory_usage=$(free 2>/dev/null | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}' || echo "0")

    # Pi metrics
    local pi_lucidia_status=$(ping -c 1 -W 2 192.168.4.38 &>/dev/null && echo "1" || echo "0")
    local pi_blackroad_status=$(ping -c 1 -W 2 192.168.4.64 &>/dev/null && echo "1" || echo "0")

    # Deployment metrics
    local recent_deployments=$(find ~/.blackroad/deployments/history -name "*.json" -mmin -60 2>/dev/null | wc -l | tr -d ' ')
    local failed_deployments=$(find ~/.blackroad/deployments/history -name "*.json" -mmin -60 -exec jq -r 'select(.status == "error") | .id' {} \; 2>/dev/null | wc -l | tr -d ' ')

    # Create metrics record
    jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson gh_rate_limit "$gh_rate_limit" \
        --argjson disk_usage "$disk_usage" \
        --argjson memory_usage "$memory_usage" \
        --argjson pi_lucidia "$pi_lucidia_status" \
        --argjson pi_blackroad "$pi_blackroad_status" \
        --argjson recent_deployments "$recent_deployments" \
        --argjson failed_deployments "$failed_deployments" \
        '{
            timestamp: $timestamp,
            github: {
                rate_limit_remaining: $gh_rate_limit
            },
            system: {
                disk_usage: $disk_usage,
                memory_usage: $memory_usage
            },
            pi_devices: {
                lucidia: $pi_lucidia,
                blackroad: $pi_blackroad
            },
            deployments: {
                recent: $recent_deployments,
                failed: $failed_deployments
            }
        }' > "$metrics_file"

    # Append to training data
    cat "$metrics_file" >> "$TRAINING_DIR/all_metrics.jsonl"

    echo "$metrics_file"
}

# Predict failures
predict_failures() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Predictive Failure Analysis                          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Collect current metrics
    local metrics_file=$(collect_metrics)
    local predictions=()

    # Rule-based predictions (simple ML)
    local disk_usage=$(jq -r '.system.disk_usage' "$metrics_file")
    local memory_usage=$(jq -r '.system.memory_usage' "$metrics_file")
    local gh_rate_limit=$(jq -r '.github.rate_limit_remaining' "$metrics_file")
    local failed_deployments=$(jq -r '.deployments.failed' "$metrics_file")

    echo -e "${BLUE}Analyzing current metrics...${NC}"
    echo ""

    # Disk space prediction
    if [ "$disk_usage" -gt 70 ]; then
        local risk_level=$((disk_usage > 85 ? 90 : 60))
        predictions+=("disk_full:$risk_level%:Disk usage at $disk_usage%, may fill within 24h")
        echo -e "${YELLOW}⚠️  PREDICTION: Disk may fill soon (${risk_level}% probability)${NC}"
    fi

    # Memory prediction
    if [ "$memory_usage" -gt 80 ]; then
        local risk_level=$((memory_usage > 90 ? 85 : 55))
        predictions+=("memory_exhaustion:$risk_level%:Memory usage at $memory_usage%")
        echo -e "${YELLOW}⚠️  PREDICTION: Memory exhaustion risk (${risk_level}% probability)${NC}"
    fi

    # GitHub rate limit prediction
    if [ "$gh_rate_limit" -lt 1000 ]; then
        local risk_level=$((gh_rate_limit < 500 ? 80 : 50))
        predictions+=("github_rate_limit:$risk_level%:Only $gh_rate_limit requests remaining")
        echo -e "${YELLOW}⚠️  PREDICTION: GitHub rate limit may be hit (${risk_level}% probability)${NC}"
    fi

    # Deployment failure prediction
    if [ "$failed_deployments" -gt 0 ]; then
        local risk_level=$((failed_deployments > 2 ? 70 : 40))
        predictions+=("deployment_pattern:$risk_level%:$failed_deployments recent failures detected")
        echo -e "${YELLOW}⚠️  PREDICTION: Deployment issues likely to continue (${risk_level}% probability)${NC}"
    fi

    # Analyze trends from historical data
    analyze_trends

    # Save predictions
    if [ ${#predictions[@]} -gt 0 ]; then
        local prediction_file="$PREDICTIONS_DIR/prediction-$(date +%s).json"

        jq -n \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --argjson predictions "$(printf '%s\n' "${predictions[@]}" | jq -R . | jq -s .)" \
            '{timestamp: $timestamp, predictions: $predictions}' \
            > "$prediction_file"

        echo ""
        echo -e "${RED}🔮 ${#predictions[@]} potential failure(s) predicted${NC}"
    else
        echo -e "${GREEN}✅ No failures predicted in next 24h${NC}"
    fi
}

# Analyze trends
analyze_trends() {
    local training_file="$TRAINING_DIR/all_metrics.jsonl"

    if [ ! -f "$training_file" ]; then
        return
    fi

    # Get last 10 metrics
    local recent_metrics=$(tail -n 10 "$training_file" 2>/dev/null)

    if [ -z "$recent_metrics" ]; then
        return
    fi

    # Calculate disk usage trend
    local disk_trend=$(echo "$recent_metrics" | jq -r '.system.disk_usage' | awk '
        {
            sum += $1
            count++
            if (NR > 1) {
                delta = $1 - prev
                if (delta > 0) increasing++
            }
            prev = $1
        }
        END {
            if (count > 1 && increasing > count/2) {
                print "increasing"
            } else {
                print "stable"
            }
        }
    ')

    if [ "$disk_trend" = "increasing" ]; then
        echo -e "${YELLOW}📈 TREND: Disk usage is increasing${NC}"
    fi

    # Calculate deployment failure trend
    local failure_trend=$(echo "$recent_metrics" | jq -r '.deployments.failed' | awk '
        {
            sum += $1
            if ($1 > 0) failures++
        }
        END {
            if (failures > 3) {
                print "concerning"
            } else {
                print "normal"
            }
        }
    ')

    if [ "$failure_trend" = "concerning" ]; then
        echo -e "${YELLOW}📈 TREND: Deployment failures increasing${NC}"
    fi
}

# Generate recommendations
generate_recommendations() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  AI Recommendations                                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Get latest prediction
    local latest_prediction=$(ls -t "$PREDICTIONS_DIR"/prediction-*.json 2>/dev/null | head -1)

    if [ -z "$latest_prediction" ]; then
        echo -e "${YELLOW}No predictions available. Run: predict first${NC}"
        return
    fi

    local predictions=$(jq -r '.predictions[]' "$latest_prediction")

    if [ -z "$predictions" ]; then
        echo -e "${GREEN}✅ No recommendations needed${NC}"
        return
    fi

    echo -e "${BLUE}Based on predictive analysis:${NC}"
    echo ""

    # Generate smart recommendations
    while IFS=':' read -r issue probability description; do
        case "$issue" in
            disk_full)
                echo -e "${MAGENTA}💡 Recommendation:${NC}"
                echo -e "   1. Run cleanup: ~/blackroad-self-healing.sh heal"
                echo -e "   2. Archive old logs: find ~/.blackroad -name '*.log' -mtime +30 -delete"
                echo -e "   3. Consider increasing disk space"
                echo ""
                ;;
            memory_exhaustion)
                echo -e "${MAGENTA}💡 Recommendation:${NC}"
                echo -e "   1. Restart memory-intensive services"
                echo -e "   2. Check for memory leaks in running processes"
                echo -e "   3. Consider upgrading RAM"
                echo ""
                ;;
            github_rate_limit)
                echo -e "${MAGENTA}💡 Recommendation:${NC}"
                echo -e "   1. Reduce API calls frequency"
                echo -e "   2. Implement request caching"
                echo -e "   3. Wait for rate limit reset"
                echo ""
                ;;
            deployment_pattern)
                echo -e "${MAGENTA}💡 Recommendation:${NC}"
                echo -e "   1. Review recent deployment failures"
                echo -e "   2. Run: ~/blackroad-deployment-verifier.sh list"
                echo -e "   3. Consider pausing deployments until issues resolved"
                echo ""
                ;;
        esac
    done <<< "$predictions"
}

# Continuous monitoring
continuous_prediction() {
    local interval="${1:-300}"  # 5 minutes default

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Continuous Predictive Monitoring                     ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Prediction interval: ${interval}s${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""

    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${MAGENTA}[$timestamp] Running predictive analysis...${NC}"
        echo ""

        predict_failures
        echo ""

        echo -e "${BLUE}Next prediction in ${interval}s...${NC}"
        echo -e "${CYAN}────────────────────────────────────────────────────────${NC}"
        echo ""

        sleep "$interval"
    done
}

# Show prediction history
show_history() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Prediction History                                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local predictions=$(ls -t "$PREDICTIONS_DIR"/prediction-*.json 2>/dev/null | head -10)

    if [ -z "$predictions" ]; then
        echo -e "${YELLOW}No prediction history${NC}"
        return
    fi

    while IFS= read -r prediction_file; do
        local timestamp=$(jq -r '.timestamp' "$prediction_file")
        local prediction_count=$(jq -r '.predictions | length' "$prediction_file")

        if [ "$prediction_count" -gt 0 ]; then
            echo -e "${YELLOW}⚠️  $timestamp - $prediction_count prediction(s)${NC}"
            jq -r '.predictions[]' "$prediction_file" | while IFS=':' read -r issue probability description; do
                echo -e "   ${RED}• $issue ($probability probability): $description${NC}"
            done
        else
            echo -e "${GREEN}✅ $timestamp - No issues predicted${NC}"
        fi
        echo ""
    done <<< "$predictions"
}

# CLI
case "${1:-menu}" in
    collect)
        collect_metrics
        echo -e "${GREEN}✅ Metrics collected${NC}"
        ;;
    predict)
        predict_failures
        ;;
    recommend)
        generate_recommendations
        ;;
    continuous)
        continuous_prediction "${2:-300}"
        ;;
    history)
        show_history
        ;;
    *)
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║  BlackRoad Predictive AI System v$PREDICTIVE_VERSION     ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  collect              Collect current metrics"
        echo "  predict              Predict potential failures"
        echo "  recommend            Generate AI recommendations"
        echo "  continuous [interval] Continuous prediction (default: 300s)"
        echo "  history              Show prediction history"
        echo ""
        echo "Example:"
        echo "  $0 predict"
        echo "  $0 recommend"
        echo "  $0 continuous 300"
        echo ""
        ;;
esac
