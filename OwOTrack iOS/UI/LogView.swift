//
//  LogView.swift
//  OwOTrack
//

import SwiftUI

//scrolling log that follows the newest line. Like the old FadeTextView, the top and bottom edges
//fade out when there is more text beyond them
struct LogView: View {
    let text: String
    let placeholder: String

    @State private var contentHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0
    @State private var offset: CGFloat = 0      //how far the text is scrolled down

    private let fade: CGFloat = 0.15            //share of the height used for the fade at each edge

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text.isEmpty ? placeholder : text)
                        .font(.system(size: 14))
                        .foregroundColor(text.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(height: 0)
                        .id("end")
                }
                .background(GeometryReader { geo in
                    Color.clear.preference(key: LogContentFrameKey.self, value: geo.frame(in: .named("log")))
                })
            }
            .coordinateSpace(name: "log")
            .background(GeometryReader { geo in
                Color.clear.preference(key: LogVisibleHeightKey.self, value: geo.size.height)
            })
            .onPreferenceChange(LogContentFrameKey.self) { frame in
                contentHeight = frame.height
                offset = -frame.minY
            }
            .onPreferenceChange(LogVisibleHeightKey.self) { height in
                visibleHeight = height
            }
            .mask(fadeMask)
            .onChange(of: text) { _ in
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    private var fadeMask: LinearGradient {
        let moreAbove = offset > 1
        let moreBelow = contentHeight - offset - visibleHeight > 1
        return LinearGradient(stops: [
            .init(color: moreAbove ? .clear : .black, location: 0),
            .init(color: .black, location: fade),
            .init(color: .black, location: 1 - fade),
            .init(color: moreBelow ? .clear : .black, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

private struct LogContentFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct LogVisibleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
