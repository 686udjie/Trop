//
//  PromptAlerts.swift
//  Trop
//
// Created by 686udjie on 13/09/2026.
//

import SwiftUI

/// Text-field prompt alert: custom field + OK/Cancel, optional message.
/// Consolidates the copy-pasted TextField alert blocks in the settings
/// screens and playlist sheets.
struct TextPromptAlert<FieldContent: View>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    var message: Text?
    var okTitle = "OK"
    var onOK: () -> Void = {}
    @ViewBuilder let field: () -> FieldContent

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            field()
            Button(okTitle, action: onOK)
            Button("Cancel", role: .cancel) {}
        } message: {
            message
        }
    }
}

/// Destructive confirmation alert: Cancel + destructive confirm, optional message.
struct DestructiveConfirm: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    var message: Text?
    let confirmTitle: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button("Cancel", role: .cancel) {}
            Button(confirmTitle, role: .destructive, action: onConfirm)
        } message: {
            message
        }
    }
}

extension View {
    func textPrompt(
        _ title: String,
        isPresented: Binding<Bool>,
        placeholder: String,
        text: Binding<String>,
        okTitle: String = "OK",
        message: Text? = nil,
        onOK: @escaping () -> Void = {}
    ) -> some View {
        modifier(TextPromptAlert(
            title: title,
            isPresented: isPresented,
            message: message,
            okTitle: okTitle,
            onOK: onOK
        ) {
            TextField(placeholder, text: text)
        })
    }

    func destructiveConfirm(
        _ title: String,
        isPresented: Binding<Bool>,
        message: Text? = nil,
        confirmTitle: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(DestructiveConfirm(
            title: title,
            isPresented: isPresented,
            message: message,
            confirmTitle: confirmTitle,
            onConfirm: onConfirm
        ))
    }
}
