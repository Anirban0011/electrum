import QtQuick 2.6
import QtQuick.Layouts 1.0
import QtQuick.Controls 2.14
import QtQuick.Controls.Material 2.0

import org.electrum 1.0

import "controls"

ElDialog {
    id: root

    title: qsTr("Open Lightning Channel")
    iconSource: Qt.resolvedUrl('../../icons/lightning.png')

    padding: 0

    width: parent.width
    height: parent.height

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Flickable {
            Layout.preferredWidth: parent.width
            Layout.fillHeight: true

            leftMargin: constants.paddingLarge
            rightMargin: constants.paddingLarge

            contentHeight: rootLayout.height
            clip:true
            interactive: height < contentHeight

            GridLayout {
                id: rootLayout
                width: parent.width

                columns: 4

                Label {
                    text: qsTr('Node')
                    color: Material.accentColor
                }

                // gossip
                TextArea {
                    id: node
                    visible: Config.useGossip
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    font.family: FixedFont
                    wrapMode: Text.Wrap
                    placeholderText: qsTr('Paste or scan node uri/pubkey')
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            channelopener.connectStr = text
                    }
                }

                RowLayout {
                    visible: Config.useGossip
                    spacing: 0
                    ToolButton {
                        icon.source: '../../icons/paste.png'
                        icon.height: constants.iconSizeMedium
                        icon.width: constants.iconSizeMedium
                        onClicked: {
                            if (channelopener.validate_connect_str(AppController.clipboardToText())) {
                                channelopener.connectStr = AppController.clipboardToText()
                                node.text = channelopener.connectStr
                            }
                        }
                    }
                    ToolButton {
                        icon.source: '../../icons/qrcode.png'
                        icon.height: constants.iconSizeMedium
                        icon.width: constants.iconSizeMedium
                        scale: 1.2
                        onClicked: {
                            var page = app.stack.push(Qt.resolvedUrl('Scan.qml'))
                            page.onFound.connect(function() {
                                if (channelopener.validate_connect_str(page.scanData)) {
                                    channelopener.connectStr = page.scanData
                                    node.text = channelopener.connectStr
                                }
                                app.stack.pop()
                            })
                        }
                    }
                }

                // trampoline
                ComboBox {
                    visible: !Config.useGossip
                    Layout.columnSpan: 3
                    Layout.fillWidth: true
                    model: channelopener.trampolineNodeNames
                    onCurrentValueChanged: {
                        if (activeFocus)
                            channelopener.connectStr = currentValue
                    }
                    // preselect a random node
                    Component.onCompleted: {
                        if (!Config.useGossip) {
                            currentIndex = Math.floor(Math.random() * channelopener.trampolineNodeNames.length)
                            channelopener.connectStr = currentValue
                        }
                    }
                }

                Label {
                    text: qsTr('Amount')
                    color: Material.accentColor
                }

                BtcField {
                    id: amount
                    fiatfield: amountFiat
                    Layout.preferredWidth: parent.width /3
                    onTextChanged: channelopener.amount = Config.unitsToSats(amount.text)
                    enabled: !is_max.checked
                }

                RowLayout {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    Label {
                        text: Config.baseUnit
                        color: Material.accentColor
                    }
                    Switch {
                        id: is_max
                        text: qsTr('Max')
                        onCheckedChanged: {
                            channelopener.amount = checked ? MAX : Config.unitsToSats(amount.text)
                        }
                    }
                }

                Item { width: 1; height: 1; visible: Daemon.fx.enabled }

                FiatField {
                    id: amountFiat
                    btcfield: amount
                    visible: Daemon.fx.enabled
                    Layout.preferredWidth: parent.width /3
                    enabled: !is_max.checked
                }

                Label {
                    visible: Daemon.fx.enabled
                    text: Daemon.fx.fiatCurrency
                    color: Material.accentColor
                    Layout.fillWidth: true
                }

                Item { visible: Daemon.fx.enabled ; height: 1; width: 1 }
            }
        }

        FlatButton {
            Layout.fillWidth: true
            text: qsTr('Open Channel')
            icon.source: '../../icons/confirmed.png'
            enabled: channelopener.valid
            onClicked: channelopener.open_channel()
        }
    }

    Component {
        id: confirmOpenChannelDialog
        ConfirmTxDialog {
            title: qsTr('Confirm Open Channel')
            amountLabelText: qsTr('Channel capacity')
            sendButtonText: qsTr('Open Channel')
            finalizer: channelopener.finalizer
        }
    }

    ChannelOpener {
        id: channelopener
        wallet: Daemon.currentWallet
        onAuthRequired: {
            app.handleAuthRequired(channelopener, method)
        }
        onValidationError: {
            if (code == 'invalid_nodeid') {
                var dialog = app.messageDialog.createObject(app, { 'text': message })
                dialog.open()
            }
        }
        onConflictingBackup: {
            var dialog = app.messageDialog.createObject(app, { 'text': message, 'yesno': true })
            dialog.open()
            dialog.yesClicked.connect(function() {
                channelopener.open_channel(true)
            })
        }
        onFinalizerChanged: {
            var dialog = confirmOpenChannelDialog.createObject(app, {
                'satoshis': channelopener.amount
            })
            dialog.txaccepted.connect(function() {
                dialog.finalizer.signAndSend()
            })
            dialog.open()
        }
        onChannelOpening: {
            console.log('Channel is opening')
            app.channelOpenProgressDialog.reset()
            app.channelOpenProgressDialog.peer = peer
            app.channelOpenProgressDialog.open()
        }
        onChannelOpenError: {
            app.channelOpenProgressDialog.state = 'failed'
            app.channelOpenProgressDialog.error = message
        }
        onChannelOpenSuccess: {
            var message = qsTr('Channel established.') + ' '
                    + qsTr('This channel will be usable after %1 confirmations').arg(min_depth)
            if (!tx_complete) {
                message = message + '\n\n' + qsTr('Please sign and broadcast the funding transaction.')
                channelopener.wallet.historyModel.init_model(true) // local tx doesn't trigger model update
            }
            app.channelOpenProgressDialog.state = 'success'
            app.channelOpenProgressDialog.info = message
            if (!has_onchain_backup) {
                app.channelOpenProgressDialog.channelBackup = channelopener.channelBackup(cid)
            }
            // TODO: handle incomplete TX
            root.close()
        }
    }
}
