#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
// BagIdea AI Agents Office — native overlay shell.
// Hosts the daemon-served Layer-2 overlay in an always-on-top webview.

use tao::{
    dpi::{LogicalPosition, LogicalSize},
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::WindowBuilder,
};
use wry::WebViewBuilder;

fn main() {
    let event_loop = EventLoop::new();
    let window = WindowBuilder::new()
        .with_title("BagIdea Office")
        .with_inner_size(LogicalSize::new(560.0, 700.0))
        .with_position(LogicalPosition::new(1090.0, 40.0))
        .with_always_on_top(true)
        .build(&event_loop)
        .expect("window");

    let _webview = WebViewBuilder::new()
        .with_url("http://127.0.0.1:8787/")
        .build(&window)
        .expect("webview");

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;
        if let Event::WindowEvent {
            event: WindowEvent::CloseRequested,
            ..
        } = event
        {
            *control_flow = ControlFlow::Exit;
        }
    });
}
