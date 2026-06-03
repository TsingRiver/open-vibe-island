import SwiftUI
import OpenIslandCore

enum IslandDesignPalette {
    enum Status {
        static let waitingAggregate = Color(red: 231.0 / 255.0, green: 167.0 / 255.0, blue: 98.0 / 255.0)
        static let waitingForApproval = Color(red: 244.0 / 255.0, green: 164.0 / 255.0, blue: 164.0 / 255.0)
        static let waitingForAnswer = Color(red: 255.0 / 255.0, green: 213.0 / 255.0, blue: 138.0 / 255.0)
        static let running = Color(red: 110.0 / 255.0, green: 167.0 / 255.0, blue: 255.0 / 255.0)
        static let completed = Color(red: 111.0 / 255.0, green: 185.0 / 255.0, blue: 130.0 / 255.0)
        static let inactive = V6Palette.paper.opacity(0.38)
        static let idle = V6Palette.paper.opacity(0.35)

        static func tint(for phase: SessionPhase) -> Color {
            switch phase {
            case .waitingForApproval:
                waitingForApproval
            case .waitingForAnswer:
                waitingForAnswer
            case .running:
                running
            case .completed:
                completed
            }
        }

        static func tint(for phase: SessionPhase, presence: IslandSessionPresence) -> Color {
            if phase == .waitingForApproval || phase == .waitingForAnswer {
                return tint(for: phase)
            }

            switch presence {
            case .running:
                return running
            case .active:
                return completed
            case .inactive:
                return inactive
            }
        }
    }

    /// 高级视觉渐变色盘，用于卡片容器与发光线条
    enum Gradients {
        static let running = LinearGradient(
            colors: [Color(red: 0.18, green: 0.48, blue: 0.96), Color(red: 0.05, green: 0.28, blue: 0.73)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let waitingForApproval = LinearGradient(
            colors: [Color(red: 0.95, green: 0.41, blue: 0.41), Color(red: 0.76, green: 0.21, blue: 0.21)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let waitingForAnswer = LinearGradient(
            colors: [Color(red: 0.98, green: 0.72, blue: 0.35), Color(red: 0.81, green: 0.51, blue: 0.11)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let completed = LinearGradient(
            colors: [Color(red: 0.22, green: 0.75, blue: 0.43), Color(red: 0.11, green: 0.49, blue: 0.26)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static func gradient(for phase: SessionPhase) -> LinearGradient {
            switch phase {
            case .waitingForApproval: return waitingForApproval
            case .waitingForAnswer:   return waitingForAnswer
            case .running:            return running
            case .completed:          return completed
            }
        }
    }

    /// 用于重构的精致卡片设计系统参数
    enum Card {
        // 卡片基础半透明背景（极具暗色磨砂感）
        static let background = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.85)
        // 呼吸及状态相关的卡片环境背景微渐变（非常低的不透明度，融入底色）
        static func ambientBg(for phase: SessionPhase) -> LinearGradient {
            let baseColor = Status.tint(for: phase)
            return LinearGradient(
                colors: [baseColor.opacity(0.06), baseColor.opacity(0.01)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        
        static func ambientBg(for presence: IslandSessionPresence) -> LinearGradient {
            let baseColor: Color = {
                switch presence {
                case .running: return Status.running
                case .active: return Status.completed
                case .inactive: return Color.white
                }
            }()
            let opacity = presence == .inactive ? 0.005 : 0.04
            return LinearGradient(
                colors: [baseColor.opacity(opacity), baseColor.opacity(0.005)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

