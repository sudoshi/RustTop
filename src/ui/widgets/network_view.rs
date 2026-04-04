use iced::widget::{column, container, row, text, Space};
use iced::{Element, Length, Padding};

use crate::metrics::network::NetworkMetrics;
use crate::theme::colors;

use super::graph::graph_view;

pub fn network_view<'a, Message: 'a>(net: &NetworkMetrics) -> Element<'a, Message> {
    let title = text("Network").size(14).color(colors::ACCENT_GREEN);

    let rx_label = format!("RX: {}", NetworkMetrics::format_rate(net.total_rx_rate));
    let tx_label = format!("TX: {}", NetworkMetrics::format_rate(net.total_tx_rate));

    let rates = row![
        text(rx_label).size(12).color(colors::NET_RX_COLOR),
        Space::with_width(16),
        text(tx_label).size(12).color(colors::NET_TX_COLOR),
    ];

    let max_net = net
        .rx_history
        .iter()
        .chain(net.tx_history.iter())
        .cloned()
        .fold(1024.0_f64, f64::max);

    let rx_f32: Vec<f32> = net.rx_history.iter().map(|v| *v as f32).collect();
    let tx_f32: Vec<f32> = net.tx_history.iter().map(|v| *v as f32).collect();

    let rx_graph = graph_view(
        &rx_f32,
        max_net as f32,
        colors::NET_RX_COLOR,
        "Download",
        &NetworkMetrics::format_rate(net.total_rx_rate),
    );

    let tx_graph = graph_view(
        &tx_f32,
        max_net as f32,
        colors::NET_TX_COLOR,
        "Upload",
        &NetworkMetrics::format_rate(net.total_tx_rate),
    );

    container(
        column![title, rates, rx_graph, tx_graph]
            .spacing(4)
            .height(Length::Fill),
    )
    .padding(Padding::from([8, 12]))
    .style(|_theme: &iced::Theme| container::Style {
        background: Some(colors::SURFACE.into()),
        border: iced::Border {
            color: colors::SURFACE_BORDER,
            width: 1.0,
            radius: 6.0.into(),
        },
        ..Default::default()
    })
    .width(Length::Fill)
    .height(Length::Fill)
    .into()
}
